import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/profile.dart';
import '../ui/dialogs.dart';
import 'store.dart';

typedef LogFn = void Function(String line);

/// Builds an authenticated [SSHClient] for a profile: jump hosts, host key
/// verification, key/password/keyboard-interactive auth.
class SshConnector {
  SshConnector(this.store);

  final Store store;

  Future<List<SSHClient>> connect(SshProfile profile,
      {LogFn? log, void Function(String banner)? onBanner}) async {
    final chain = <SshProfile>[];
    var current = profile;
    final seen = <String>{profile.id};
    while (current.jumpHostId != null) {
      final jump = store.profileById(current.jumpHostId);
      if (jump == null) break;
      if (!seen.add(jump.id)) throw Exception('Jump host loop detected');
      chain.insert(0, jump);
      current = jump;
    }
    chain.add(profile);

    final clients = <SSHClient>[];
    try {
      for (final p in chain) {
        final via = clients.isEmpty ? null : clients.last;
        log?.call(via == null
            ? 'Connecting to ${p.host}:${p.port}…'
            : 'Connecting to ${p.host}:${p.port} via ${chain[clients.length - 1].displayName}…');
        clients.add(await _connectOne(p, via: via, log: log, onBanner: onBanner));
      }
    } catch (_) {
      for (final c in clients.reversed) {
        c.close();
      }
      rethrow;
    }
    return clients;
  }

  Future<SSHClient> _connectOne(SshProfile p,
      {SSHClient? via, LogFn? log, void Function(String)? onBanner}) async {
    final timeout = Duration(seconds: p.readyTimeout <= 0 ? 20 : p.readyTimeout);
    final SSHSocket socket = via != null
        ? await via.forwardLocal(p.host, p.port).timeout(timeout)
        : await SSHSocket.connect(p.host, p.port, timeout: timeout);

    final identities = <SSHIdentity>[];
    if (p.auth == AuthType.auto || p.auth == AuthType.publicKey) {
      identities.addAll(await _loadIdentities(p, log));
    }

    String? storedPassword = await store.passwordFor(p.id);
    var passwordTries = 0;
    final hostPort = '${p.host}:${p.port}';

    final client = SSHClient(
      socket,
      username: p.user,
      identities: identities,
      keepAliveInterval:
          p.keepaliveInterval > 0 ? Duration(seconds: p.keepaliveInterval) : null,
      handshakeTimeout: timeout,
      onVerifyHostKey: (type, fpBytes) async {
        final fp = utf8.decode(fpBytes);
        final value = '$type $fp';
        final known = store.knownHosts[hostPort];
        if (known == value) return true;
        final decision = await confirmHostKey(
          host: hostPort,
          type: type,
          fingerprint: fp,
          previous: known,
        );
        if (decision == HostKeyDecision.acceptAndSave) {
          store.setKnownHost(hostPort, value);
        }
        if (decision == HostKeyDecision.reject) log?.call('Host key rejected');
        return decision != HostKeyDecision.reject;
      },
      onUserauthBanner: onBanner,
      onPasswordRequest: (p.auth == AuthType.publicKey)
          ? null
          : () async {
              passwordTries++;
              if (storedPassword != null && passwordTries == 1) {
                return storedPassword;
              }
              if (passwordTries > 3) return null;
              final r = await promptSecret(
                title: 'Password for ${p.address}',
                message: passwordTries > 1 ? 'Authentication failed, try again.' : null,
              );
              if (r == null) return null;
              if (r.remember) {
                await store.savePassword(p.id, r.value);
                storedPassword = r.value;
              }
              return r.value;
            },
      onUserInfoRequest: (p.auth == AuthType.publicKey)
          ? null
          : (request) async {
              // Answer a single hidden "Password:" prompt with the stored password once.
              if (request.prompts.length == 1 &&
                  !request.prompts.first.echo &&
                  request.prompts.first.promptText.toLowerCase().contains('password') &&
                  storedPassword != null &&
                  passwordTries == 0) {
                passwordTries++;
                return [storedPassword!];
              }
              passwordTries++;
              return keyboardInteractive(request);
            },
    );

    try {
      await client.authenticated;
    } catch (e) {
      client.close();
      rethrow;
    }
    log?.call('Authenticated as ${p.user}@${p.host}');
    return client;
  }

  Future<List<SSHKeyPair>> _loadIdentities(SshProfile p, LogFn? log) async {
    if (p.keyId == null) return [];
    final key = store.keyById(p.keyId);
    final pem = await store.keyPem(p.keyId!);
    if (key == null || pem == null) {
      log?.call('Selected private key is missing');
      return [];
    }
    String? passphrase;
    if (SSHKeyPair.isEncryptedPem(pem)) {
      passphrase = await store.keyPassphrase(key.id);
      for (var attempt = 0; attempt < 3; attempt++) {
        if (passphrase != null) {
          try {
            return SSHKeyPair.fromPem(pem, passphrase);
          } catch (_) {}
        }
        final r = await promptSecret(
          title: 'Passphrase for key "${key.name}"',
          label: 'Passphrase',
          message: attempt > 0 ? 'Wrong passphrase, try again.' : null,
        );
        if (r == null) return [];
        passphrase = r.value;
        if (r.remember) {
          try {
            final pairs = SSHKeyPair.fromPem(pem, passphrase);
            await store.saveKey(key, pem: pem, passphrase: passphrase);
            return pairs;
          } catch (_) {}
        }
      }
      return [];
    }
    return SSHKeyPair.fromPem(pem);
  }
}
