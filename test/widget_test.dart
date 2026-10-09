import 'package:flutter_test/flutter_test.dart';
import 'package:nabby/models/profile.dart';
import 'package:nabby/services/keys.dart';
import 'package:nabby/services/tabby_import.dart';

void main() {
  test('quick connect parsing', () {
    final a = SshProfile.parseQuick('nero@10.0.0.5:2222')!;
    expect([a.user, a.host, a.port], ['nero', '10.0.0.5', 2222]);
    final b = SshProfile.parseQuick('example.com')!;
    expect([b.user, b.host, b.port], ['root', 'example.com', 22]);
    final c = SshProfile.parseQuick('me@[::1]:22')!;
    expect([c.user, c.host, c.port], ['me', '::1', 22]);
    expect(SshProfile.parseQuick('  '), isNull);
  });

  test('profile json roundtrip', () {
    final p = SshProfile(host: 'h', user: 'u', forwards: [
      PortForward(type: ForwardType.dynamic, port: 1080),
    ]);
    final q = SshProfile.fromJson(p.toJson());
    expect(q.id, p.id);
    expect(q.forwards.single.type, ForwardType.dynamic);
  });

  test('tabby config import', () {
    const yaml = '''
version: 8
groups:
  - id: g1
    name: Work
profiles:
  - type: local
    name: shell
  - type: ssh
    name: Bastion
    id: ssh:custom:bastion
    options:
      host: bastion.example.com
      user: admin
  - type: ssh
    name: Internal
    group: g1
    options:
      host: 10.1.1.1
      port: 2200
      user: deploy
      auth: publicKey
      jumpHost: ssh:custom:bastion
      forwardedPorts:
        - type: Local
          host: 127.0.0.1
          port: 8080
          targetAddress: 127.0.0.1
          targetPort: 80
''';
    final list = TabbyImport.parse(yaml);
    expect(list.length, 2);
    final internal = list[1];
    expect(internal.group, 'Work');
    expect(internal.port, 2200);
    expect(internal.auth, AuthType.publicKey);
    expect(internal.jumpHostId, list[0].id);
    expect(internal.forwards.single.targetPort, 80);
  });

  test('ed25519 key generation roundtrip', () {
    final k = KeyTools.generateEd25519('test@nabby');
    expect(k.publicLine, startsWith('ssh-ed25519 '));
    expect(KeyTools.validate(k.pem), k.publicLine.replaceFirst(' test@nabby', ''));
    final enc = KeyTools.generateEd25519('x', passphrase: 'secret');
    expect(KeyTools.isEncrypted(enc.pem), isTrue);
    expect(() => KeyTools.validate(enc.pem, passphrase: 'wrong'), throwsA(anything));
    expect(KeyTools.validate(enc.pem, passphrase: 'secret'), startsWith('ssh-ed25519 '));
  });
}
