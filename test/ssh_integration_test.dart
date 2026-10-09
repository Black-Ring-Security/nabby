// End-to-end test against a real sshd. Run with:
//   NABBY_TEST_DIR=<dir with user_key, user_rsa> NABBY_TEST_HOSTKEY="ssh-ed25519 SHA256:..." \
//   flutter test test/ssh_integration_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nabby/models/profile.dart';
import 'package:nabby/services/keys.dart';
import 'package:nabby/services/session.dart';
import 'package:nabby/services/settings.dart';
import 'package:nabby/services/ssh_connector.dart';
import 'package:nabby/services/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final dir = Platform.environment['NABBY_TEST_DIR'];
  final hostKey = Platform.environment['NABBY_TEST_HOSTKEY'];
  final skip = dir == null || hostKey == null ? 'set NABBY_TEST_DIR and NABBY_TEST_HOSTKEY' : null;
  final user = Platform.environment['USER'] ?? 'root';

  if (skip != null) {
    test('ssh integration', () {}, skip: skip);
    return;
  }

  late Store store;
  late AppSettings settings;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final secure = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        switch (call.method) {
          case 'read':
            return secure[args['key']];
          case 'write':
            secure[args['key']] = args['value'];
            return null;
          case 'delete':
            secure.remove(args['key']);
            return null;
        }
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = Store(prefs);
    settings = AppSettings(prefs);
    store.setKnownHost('127.0.0.1:2222', hostKey ?? '');
  });

  Future<SshProfile> profileWithKey(String file, {String? passphrase}) async {
    final pem = File('$dir/$file').readAsStringSync();
    final pub = KeyTools.validate(pem, passphrase: passphrase);
    final k = StoredKey(name: file, publicKey: pub, type: pub.split(' ').first);
    await store.saveKey(k, pem: pem, passphrase: passphrase);
    final p = SshProfile(
        name: 'local', host: '127.0.0.1', port: 2222, user: user,
        auth: AuthType.publicKey, keyId: k.id);
    await store.saveProfile(p);
    return p;
  }

  Future<String> waitFor(TerminalSession s, String needle) async {
    for (var i = 0; i < 100; i++) {
      final text = s.terminal.buffer.getText();
      if (text.contains(needle)) return text;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    fail('Timed out waiting for "$needle". Screen:\n${s.terminal.buffer.getText()}');
  }

  test('terminal session with ed25519 key, startup command and resize', () async {
    final p = await profileWithKey('user_key');
    p.startupCommand = 'echo startup-\$((40+2))';
    final s = TerminalSession(profile: p, store: store, settings: settings);
    s.terminal.resize(100, 30);
    await s.connect();
    expect(s.state, SessionState.connected, reason: s.error);
    await waitFor(s, 'startup-42');
    s.terminal.textInput('stty size; echo done-\$((2*3))\r');
    final text = await waitFor(s, 'done-6');
    expect(text, contains('30 100'));
    // Sticky ctrl from the extra-keys bar: Ctrl+C interrupts a sleeping command.
    s.terminal.textInput('sleep 30\r');
    await Future.delayed(const Duration(milliseconds: 300));
    s.toggleCtrl();
    s.terminal.textInput('c');
    expect(s.ctrlLatched, isFalse);
    s.terminal.textInput('echo after-int\r');
    await waitFor(s, 'after-int');
    await s.close();
  });

  test('encrypted RSA key with stored passphrase', () async {
    final p = await profileWithKey('user_rsa', passphrase: 'pass123');
    final clients = await SshConnector(store).connect(p);
    final out = await clients.last.run('echo rsa-ok');
    expect(utf8.decode(out).trim(), 'rsa-ok');
    clients.last.close();
  });

  test('changed host key is rejected', () async {
    final p = await profileWithKey('user_key');
    store.setKnownHost('127.0.0.1:2222', 'ssh-ed25519 SHA256:bogus');
    await expectLater(SshConnector(store).connect(p), throwsA(anything));
  });

  test('jump host chain', () async {
    final jump = await profileWithKey('user_key');
    final target = SshProfile(
        name: 'behind', host: '127.0.0.1', port: 2222, user: user,
        auth: AuthType.publicKey, keyId: jump.keyId, jumpHostId: jump.id);
    await store.saveProfile(target);
    final logs = <String>[];
    final clients = await SshConnector(store).connect(target, log: logs.add);
    expect(clients.length, 2);
    expect(logs.join('\n'), contains('via local'));
    final out = await clients.last.run('echo jumped');
    expect(utf8.decode(out).trim(), 'jumped');
    for (final c in clients.reversed) {
      c.close();
    }
  });

  test('local port forward', () async {
    final p = await profileWithKey('user_key');
    p.forwards.add(PortForward(
        type: ForwardType.local, host: '127.0.0.1', port: 18022,
        targetAddress: '127.0.0.1', targetPort: 2222));
    final s = TerminalSession(profile: p, store: store, settings: settings);
    await s.connect();
    expect(s.activeForwards, hasLength(1));
    final sock = await Socket.connect('127.0.0.1', 18022);
    final banner = await sock.first.timeout(const Duration(seconds: 5));
    expect(utf8.decode(banner), startsWith('SSH-2.0'));
    sock.destroy();
    await s.close();
  });

  test('sftp operations', () async {
    final p = await profileWithKey('user_key');
    final clients = await SshConnector(store).connect(p);
    final sftp = await clients.last.sftp();
    final home = await sftp.absolute('.');
    final base = '$home/.nabby-test-${DateTime.now().millisecondsSinceEpoch}';
    await sftp.mkdir(base);
    final f = await sftp.open('$base/a.txt',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    final payload = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    await f.write(Stream.value(payload)).done;
    await f.close();
    final names = (await sftp.listdir(base)).map((e) => e.filename).toList();
    expect(names, contains('a.txt'));
    await sftp.rename('$base/a.txt', '$base/b.txt');
    final r = await sftp.open('$base/b.txt');
    final sink = _Collect();
    await r.downloadTo(sink);
    await r.close();
    expect(sink.bytes.toBytes(), payload);
    await sftp.setStat('$base/b.txt', SftpFileAttrs(mode: SftpFileMode.value(0x8000 | int.parse('640', radix: 8))));
    expect((await sftp.stat('$base/b.txt')).mode!.value & 0x1FF, int.parse('640', radix: 8));
    await sftp.remove('$base/b.txt');
    await sftp.rmdir(base);
    sftp.close();
    clients.last.close();
  });
}

class _Collect implements StreamSink<List<int>> {
  final bytes = BytesBuilder();
  final _done = Completer<void>();
  @override
  void add(List<int> data) => bytes.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => stream.forEach(add);
  @override
  Future close() async => _done.complete();
  @override
  Future get done => _done.future;
}
