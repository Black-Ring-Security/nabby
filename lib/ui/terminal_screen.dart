import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/xterm.dart';

import '../models/profile.dart';
import '../services/color_schemes.dart';
import '../services/session.dart';
import '../services/settings.dart';
import '../services/store.dart';
import 'dialogs.dart';
import 'extra_keys.dart';
import 'profile_edit_screen.dart' show editForward;
import 'sftp_screen.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final Map<TerminalSession, FocusNode> _focus = {};
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartFont = 13;

  @override
  void initState() {
    super.initState();
    if (context.read<AppSettings>().keepScreenOn) WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _focusFor(TerminalSession s) => _focus.putIfAbsent(s, FocusNode.new);

  Future<void> _paste(TerminalSession s) async {
    final warn = context.read<AppSettings>().warnOnMultilinePaste;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    if (warn && text.contains('\n')) {
      final lines = text.split('\n').length;
      if (!await confirm('Paste multiple lines?',
          'You are about to paste $lines lines. They may run as commands.',
          ok: 'Paste')) {
        return;
      }
    }
    s.terminal.paste(text);
  }

  void _copy(TerminalSession s) {
    final sel = s.controller.selection;
    if (sel == null) {
      toast('Nothing selected. Long-press to select text.');
      return;
    }
    Clipboard.setData(ClipboardData(text: s.terminal.buffer.getText(sel)));
    s.controller.clearSelection();
    toast('Copied');
  }

  Future<void> _closeTab(TerminalSession s) async {
    final mgr = context.read<SessionManager>();
    if (context.read<AppSettings>().confirmClose && s.state == SessionState.connected) {
      if (!await confirm('Close tab', 'Disconnect from ${s.profile.displayName}?',
          ok: 'Close')) {
        return;
      }
    }
    _focus.remove(s)?.dispose();
    await mgr.closeSession(s);
    if (mgr.sessions.isEmpty && mounted) Navigator.pop(context);
  }

  Future<void> _newTab() async {
    final store = context.read<Store>();
    final mgr = context.read<SessionManager>();
    final p = await showModalBottomSheet<SshProfile>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, sc) => ListView(controller: sc, children: [
          const ListTile(title: Text('Open new tab', style: TextStyle(fontWeight: FontWeight.bold))),
          if (mgr.active != null)
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: Text('Duplicate "${mgr.active!.profile.displayName}"'),
              onTap: () => Navigator.pop(ctx, mgr.active!.profile),
            ),
          const Divider(),
          for (final p in store.profiles)
            ListTile(
              leading: CircleAvatar(
                radius: 6,
                backgroundColor: Color(p.color ?? Theme.of(ctx).colorScheme.primary.toARGB32()),
              ),
              title: Text(p.displayName),
              subtitle: Text(p.address),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (p != null) mgr.open(p);
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartFont = context.read<AppSettings>().fontSize;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _pinchStartDistance != null && _pinchStartDistance! > 0) {
      final pts = _pointers.values.toList();
      final scale = (pts[0] - pts[1]).distance / _pinchStartDistance!;
      final size = (_pinchStartFont * scale).clamp(6.0, 32.0).roundToDouble();
      final settings = context.read<AppSettings>();
      if (size != settings.fontSize) settings.update((s) => s.fontSize = size);
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
  }

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<SessionManager>();
    final settings = context.watch<AppSettings>();
    final active = mgr.active;
    if (active == null) {
      // All tabs were closed (e.g. "Disconnect all" from the notification).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
      return const Scaffold(body: Center(child: Text('No open sessions')));
    }
    final scheme = ColorSchemes.byName(active.profile.colorScheme ?? settings.colorScheme);
    final theme = scheme.toTerminalTheme();

    return Scaffold(
      backgroundColor: scheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _TabStrip(
            manager: mgr,
            onClose: _closeTab,
            onNew: _newTab,
            menu: _menu(active),
          ),
          if (active.state == SessionState.connecting)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: IndexedStack(
                index: mgr.activeIndex.clamp(0, mgr.sessions.length - 1),
                children: [
                  for (final s in mgr.sessions)
                    _SessionView(
                      key: ObjectKey(s),
                      session: s,
                      focusNode: _focusFor(s),
                      theme: ColorSchemes.byName(s.profile.colorScheme ?? settings.colorScheme)
                          .toTerminalTheme(),
                      settings: settings,
                      isActive: s == active,
                    ),
                ],
              ),
            ),
          ),
          if (active.activeForwards.isNotEmpty)
            Container(
              width: double.infinity,
              color: theme.background,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text('⇄ ${active.activeForwards.join('   ')}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: theme.brightBlack)),
            ),
          if (settings.showExtraKeys)
            ListenableBuilder(
              listenable: active,
              builder: (_, _) => ExtraKeysBar(session: active, onPaste: () => _paste(active)),
            ),
        ]),
      ),
    );
  }

  Widget _menu(TerminalSession s) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) async {
        final settings = context.read<AppSettings>();
        switch (v) {
          case 'sftp':
            final client = s.client;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => client != null
                    ? SftpScreen(profile: s.profile, client: client)
                    : SftpScreen(profile: s.profile),
              ),
            );
          case 'paste':
            _paste(s);
          case 'copy':
            _copy(s);
          case 'selectall':
            final b = s.terminal.buffer;
            s.controller.setSelection(
              b.createAnchor(0, 0),
              b.createAnchor(s.terminal.viewWidth, b.lines.length - 1),
            );
          case 'keyboard':
            _focusFor(s).requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
          case 'bigger':
            settings.update((x) => x.fontSize = (x.fontSize + 1).clamp(6, 32));
          case 'smaller':
            settings.update((x) => x.fontSize = (x.fontSize - 1).clamp(6, 32));
          case 'keys':
            settings.update((x) => x.showExtraKeys = !x.showExtraKeys);
          case 'forward':
            final f = await editForward(context, null);
            if (f != null) await s.addForward(f);
          case 'clear':
            s.terminal.buffer.clear();
            s.terminal.buffer.setCursor(0, 0);
            s.terminal.textInput('\x0c');
          case 'reconnect':
            s.connect();
          case 'duplicate':
            context.read<SessionManager>().duplicate(s);
          case 'close':
            _closeTab(s);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'sftp', child: _MenuRow(Icons.folder_open, 'SFTP files')),
        const PopupMenuItem(value: 'paste', child: _MenuRow(Icons.content_paste, 'Paste')),
        const PopupMenuItem(value: 'copy', child: _MenuRow(Icons.copy, 'Copy selection')),
        const PopupMenuItem(value: 'selectall', child: _MenuRow(Icons.select_all, 'Select all')),
        const PopupMenuItem(value: 'keyboard', child: _MenuRow(Icons.keyboard, 'Show keyboard')),
        const PopupMenuItem(value: 'bigger', child: _MenuRow(Icons.zoom_in, 'Bigger font')),
        const PopupMenuItem(value: 'smaller', child: _MenuRow(Icons.zoom_out, 'Smaller font')),
        const PopupMenuItem(value: 'keys', child: _MenuRow(Icons.keyboard_alt_outlined, 'Toggle extra keys')),
        if (s.state == SessionState.connected)
          const PopupMenuItem(value: 'forward', child: _MenuRow(Icons.swap_horiz, 'Add port forward')),
        const PopupMenuItem(value: 'clear', child: _MenuRow(Icons.cleaning_services, 'Clear')),
        const PopupMenuItem(value: 'reconnect', child: _MenuRow(Icons.refresh, 'Reconnect')),
        const PopupMenuItem(value: 'duplicate', child: _MenuRow(Icons.copy_all, 'Duplicate tab')),
        const PopupMenuItem(value: 'close', child: _MenuRow(Icons.close, 'Close tab')),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]);
}

class _SessionView extends StatelessWidget {
  const _SessionView({
    super.key,
    required this.session,
    required this.focusNode,
    required this.theme,
    required this.settings,
    required this.isActive,
  });

  final TerminalSession session;
  final FocusNode focusNode;
  final TerminalTheme theme;
  final AppSettings settings;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      session.terminal,
      controller: session.controller,
      focusNode: focusNode,
      autofocus: isActive,
      theme: theme,
      padding: const EdgeInsets.all(4),
      cursorType: settings.cursorType,
      keyboardType: TextInputType.visiblePassword,
      keyboardAppearance:
          theme.background.computeLuminance() < 0.4 ? Brightness.dark : Brightness.light,
      deleteDetection: true,
      textStyle: TerminalStyle(
        fontSize: settings.fontSize,
        fontFamily: settings.fontFamily,
        fontFamilyFallback: const ['monospace', 'Noto Sans Mono', 'Noto Color Emoji'],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.manager,
    required this.onClose,
    required this.onNew,
    required this.menu,
  });

  final SessionManager manager;
  final void Function(TerminalSession) onClose;
  final VoidCallback onNew;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          IconButton(
            tooltip: 'Hosts',
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: manager.sessions.length,
              onReorderItem: manager.reorder,
              itemBuilder: (ctx, i) {
                final s = manager.sessions[i];
                final selected = i == manager.activeIndex;
                final tag = Color(s.profile.color ?? cs.primary.toARGB32());
                final dot = switch (s.state) {
                  SessionState.connected => Colors.greenAccent,
                  SessionState.connecting => Colors.amber,
                  SessionState.disconnected => Colors.grey,
                  SessionState.failed => Colors.redAccent,
                };
                return ReorderableDelayedDragStartListener(
                  key: ObjectKey(s),
                  index: i,
                  child: GestureDetector(
                    onTap: () => manager.activate(i),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      padding: const EdgeInsets.only(left: 10),
                      decoration: BoxDecoration(
                        color: selected ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border(bottom: BorderSide(color: selected ? tag : Colors.transparent, width: 2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle, size: 8, color: dot),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(s.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                        ),
                        InkWell(
                          onTap: () => onClose(s),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, size: 14),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'New tab',
            icon: const Icon(Icons.add, size: 20),
            onPressed: onNew,
          ),
          menu,
        ]),
      ),
    );
  }
}
