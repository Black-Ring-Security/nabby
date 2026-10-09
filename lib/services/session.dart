import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models/profile.dart';
import 'keepalive.dart';
import 'settings.dart';
import 'ssh_connector.dart';
import 'store.dart';

enum SessionState { connecting, connected, disconnected, failed }

/// One terminal tab: an SSH shell rendered by xterm, plus its port forwards.
class TerminalSession extends ChangeNotifier {
  TerminalSession({required this.profile, required this.store, required this.settings})
      : terminal = Terminal(maxLines: settings.scrollback) {
    controller = TerminalController();
    terminal.onOutput = _onInput;
    terminal.onResize = (w, h, pw, ph) {
      _shell?.resizeTerminal(w, h, pw, ph);
    };
    terminal.onTitleChange = (t) {
      remoteTitle = t;
      notifyListeners();
    };
    terminal.onBell = () {
      if (settings.vibrateOnBell) HapticFeedback.mediumImpact();
    };
  }

  final SshProfile profile;
  final Store store;
  final AppSettings settings;
  final Terminal terminal;
  late final TerminalController controller;

  SessionState state = SessionState.connecting;
  String? remoteTitle;
  String? error;
  final List<String> activeForwards = [];

  List<SSHClient> _clients = [];
  SSHSession? _shell;
  final List<StreamSubscription> _subs = [];
  final List<ServerSocket> _localServers = [];
  final List<SSHRemoteForward> _remoteForwards = [];
  final List<SSHDynamicForward> _dynamicForwards = [];
  bool _closed = false;

  SSHClient? get client => _clients.isEmpty ? null : _clients.last;
  String get title => remoteTitle?.isNotEmpty == true ? remoteTitle! : profile.displayName;

  void _log(String line) => terminal.write('\x1b[36m$line\x1b[0m\r\n');

  /// Sticky Ctrl/Alt from the extra-keys bar, applied to the next typed key.
  bool ctrlLatched = false;
  bool altLatched = false;

  void toggleCtrl() {
    ctrlLatched = !ctrlLatched;
    notifyListeners();
  }

  void toggleAlt() {
    altLatched = !altLatched;
    notifyListeners();
  }

  /// Sends a special key from the extra-keys bar, honouring latched modifiers.
  void sendKey(TerminalKey key) {
    final ctrl = ctrlLatched, alt = altLatched;
    _clearLatches();
    terminal.keyInput(key, ctrl: ctrl, alt: alt);
  }

  void _clearLatches() {
    if (!ctrlLatched && !altLatched) return;
    ctrlLatched = false;
    altLatched = false;
    notifyListeners();
  }

  String _applyLatches(String data) {
    if (!ctrlLatched && !altLatched) return data;
    if (data.isEmpty || data.startsWith('\x1b')) return data;
    var out = data;
    if (ctrlLatched && data.length == 1) {
      final c = data.toLowerCase().codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7a) {
        out = String.fromCharCode(c - 0x60);
      } else if (c >= 0x5b && c <= 0x5f) {
        out = String.fromCharCode(c - 0x40);
      } else if (c == 0x20 || c == 0x40) {
        out = '\x00';
      } else if (c == 0x3f) {
        out = '\x7f';
      }
    }
    if (altLatched) out = '\x1b$out';
    _clearLatches();
    return out;
  }

  void _onInput(String data) {
    data = _applyLatches(data);
    final shell = _shell;
    if (shell == null) {
      // Enter on a dead session reconnects, like Tabby's "Press any key to reconnect".
      if ((state == SessionState.disconnected || state == SessionState.failed) &&
          (data == '\r' || data == '\n')) {
        connect();
      }
      return;
    }
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  Future<void> connect() async {
    if (_closed) return;
    await _teardown();
    state = SessionState.connecting;
    error = null;
    notifyListeners();
    try {
      _clients = await SshConnector(store).connect(
        profile,
        log: _log,
        onBanner: (b) => terminal.write(b.replaceAll('\n', '\r\n')),
      );
      if (_closed) {
        await _teardown();
        return;
      }
      // Let the TerminalView lay out first so the PTY starts at the real size.
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(milliseconds: 500), onTimeout: () {});
      final shell = await client!.shell(
        pty: SSHPtyConfig(
          type: profile.term.isEmpty ? 'xterm-256color' : profile.term,
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      _shell = shell;
      shell.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      _subs.add(shell.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write));
      _subs.add(shell.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write));
      state = SessionState.connected;
      store.touchProfile(profile);
      notifyListeners();

      shell.done.then((_) => _onClosed(null));
      client!.done.then((_) => _onClosed(null), onError: (e) => _onClosed(e));

      await _startForwards(profile.forwards);

      if (profile.startupCommand.trim().isNotEmpty) {
        for (final line in profile.startupCommand.split('\n')) {
          if (line.trim().isEmpty) continue;
          shell.write(Uint8List.fromList(utf8.encode('$line\r')));
        }
      }
    } catch (e) {
      error = _describe(e);
      state = SessionState.failed;
      terminal.write('\r\n\x1b[31m✖ ${error!}\x1b[0m\r\n');
      terminal.write('\x1b[36mPress Enter to reconnect\x1b[0m\r\n');
      await _teardown();
      notifyListeners();
    }
  }

  static String _describe(Object e) {
    if (e is SocketException) return 'Connection failed: ${e.osError?.message ?? e.message}';
    if (e is TimeoutException) return 'Connection timed out';
    if (e is SSHAuthFailError) return 'Authentication failed';
    if (e is SSHAuthAbortError) return 'Authentication aborted';
    if (e is SSHHostkeyError) return 'Host key verification failed';
    return e.toString();
  }

  void _onClosed(Object? e) {
    if (state != SessionState.connected) return;
    state = SessionState.disconnected;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      BackgroundKeepAlive.notify(
          'Disconnected from ${profile.displayName}',
          e != null ? _describe(e) : 'The SSH session was closed');
    }
    _shell = null;
    terminal.write('\r\n\x1b[33m● Session closed${e != null ? ': ${_describe(e)}' : ''}\x1b[0m\r\n');
    terminal.write('\x1b[36mPress Enter to reconnect\x1b[0m\r\n');
    _teardown();
    notifyListeners();
  }

  Future<void> _startForwards(List<PortForward> forwards) async {
    final c = client!;
    for (final f in forwards) {
      try {
        switch (f.type) {
          case ForwardType.local:
            final server = await ServerSocket.bind(f.host, f.port);
            _localServers.add(server);
            server.listen((socket) async {
              try {
                final channel = await c.forwardLocal(f.targetAddress, f.targetPort);
                channel.stream.cast<List<int>>().pipe(socket).catchError((_) {});
                socket.cast<List<int>>().pipe(channel.sink).catchError((_) {});
              } catch (_) {
                socket.destroy();
              }
            });
          case ForwardType.remote:
            final fwd = await c.forwardRemote(host: f.host, port: f.port);
            if (fwd == null) throw Exception('server refused');
            _remoteForwards.add(fwd);
            fwd.connections.listen((channel) async {
              try {
                final socket = await Socket.connect(f.targetAddress, f.targetPort);
                channel.stream.cast<List<int>>().pipe(socket).catchError((_) {});
                socket.cast<List<int>>().pipe(channel.sink).catchError((_) {});
              } catch (_) {
                channel.destroy();
              }
            });
          case ForwardType.dynamic:
            _dynamicForwards.add(await c.forwardDynamic(bindHost: f.host, bindPort: f.port));
        }
        activeForwards.add(f.label);
        _log('Forwarding ${f.label}');
      } catch (e) {
        _log('Port forward ${f.label} failed: $e');
      }
    }
    notifyListeners();
  }

  /// Adds a port forward at runtime (not saved to the profile).
  Future<void> addForward(PortForward f) async {
    if (client == null) return;
    await _startForwards([f]);
  }

  Future<void> _teardown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final s in _localServers) {
      await s.close();
    }
    _localServers.clear();
    for (final f in _remoteForwards) {
      f.close();
    }
    _remoteForwards.clear();
    for (final f in _dynamicForwards) {
      await f.close();
    }
    _dynamicForwards.clear();
    activeForwards.clear();
    _shell?.close();
    _shell = null;
    for (final c in _clients.reversed) {
      c.close();
    }
    _clients = [];
  }

  Future<void> close() async {
    _closed = true;
    await _teardown();
  }

  @override
  void dispose() {
    close();
    controller.dispose();
    super.dispose();
  }
}

/// Holds all open terminal tabs, like Tabby's tab bar.
class SessionManager extends ChangeNotifier {
  SessionManager(this.store, this.settings);

  final Store store;
  final AppSettings settings;
  final List<TerminalSession> sessions = [];
  int activeIndex = 0;

  TerminalSession? get active =>
      sessions.isEmpty ? null : sessions[activeIndex.clamp(0, sessions.length - 1)];

  TerminalSession open(SshProfile profile) {
    final s = TerminalSession(profile: profile, store: store, settings: settings);
    s.addListener(notifyListeners);
    sessions.add(s);
    activeIndex = sessions.length - 1;
    notifyListeners();
    s.connect();
    return s;
  }

  TerminalSession duplicate(TerminalSession s) => open(s.profile);

  void activate(int i) {
    activeIndex = i;
    notifyListeners();
  }

  void reorder(int from, int to) {
    final active = this.active;
    final s = sessions.removeAt(from);
    sessions.insert(to, s);
    activeIndex = active == null ? 0 : sessions.indexOf(active);
    notifyListeners();
  }

  Future<void> closeSession(TerminalSession s) async {
    final i = sessions.indexOf(s);
    if (i < 0) return;
    sessions.removeAt(i);
    if (activeIndex >= sessions.length) activeIndex = sessions.length - 1;
    if (activeIndex < 0) activeIndex = 0;
    s.removeListener(notifyListeners);
    notifyListeners();
    s.dispose();
  }

  /// Closes every tab (used by the notification's "Disconnect all" action).
  Future<void> closeAll() async {
    for (final s in List.of(sessions)) {
      await closeSession(s);
    }
  }

  int get connectedCount =>
      sessions.where((s) => s.state == SessionState.connected).length;
}
