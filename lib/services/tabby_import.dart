import 'package:yaml/yaml.dart';

import '../models/profile.dart';

/// Imports SSH profiles from a Tabby desktop `config.yaml`.
/// Passwords stay in the desktop keychain and private keys are file paths there,
/// so only connection details, groups, jump hosts and port forwards come across.
class TabbyImport {
  static List<SshProfile> parse(String yamlText) {
    final doc = loadYaml(yamlText);
    if (doc is! YamlMap) throw const FormatException('Not a Tabby config file');
    final groupNames = <String, String>{};
    final groups = doc['groups'];
    if (groups is YamlList) {
      for (final g in groups) {
        if (g is YamlMap && g['id'] != null) {
          groupNames['${g['id']}'] = '${g['name'] ?? ''}';
        }
      }
    }
    final list = doc['profiles'];
    if (list is! YamlList) return [];

    final result = <SshProfile>[];
    final tabbyIds = <String, SshProfile>{};
    final jumpRefs = <SshProfile, String>{};
    for (final item in list) {
      if (item is! YamlMap || item['type'] != 'ssh') continue;
      final o = item['options'];
      if (o is! YamlMap || o['host'] == null) continue;
      final groupRaw = '${item['group'] ?? ''}';
      final p = SshProfile(
        name: '${item['name'] ?? ''}',
        group: groupNames[groupRaw] ?? groupRaw,
        host: '${o['host']}',
        port: (o['port'] as int?) ?? 22,
        user: '${o['user'] ?? 'root'}',
        auth: switch (o['auth']) {
          'password' => AuthType.password,
          'publicKey' => AuthType.publicKey,
          'keyboardInteractive' => AuthType.keyboardInteractive,
          _ => AuthType.auto,
        },
        keepaliveInterval: ((o['keepaliveInterval'] as int?) ?? 30000) ~/ 1000,
        readyTimeout: ((o['readyTimeout'] as int?) ?? 20000) ~/ 1000,
      );
      final fwds = o['forwardedPorts'];
      if (fwds is YamlList) {
        for (final f in fwds) {
          if (f is! YamlMap) continue;
          p.forwards.add(PortForward(
            type: switch (f['type']) {
              'Remote' => ForwardType.remote,
              'Dynamic' => ForwardType.dynamic,
              _ => ForwardType.local,
            },
            host: '${f['host'] ?? '127.0.0.1'}',
            port: (f['port'] as int?) ?? 0,
            targetAddress: '${f['targetAddress'] ?? '127.0.0.1'}',
            targetPort: (f['targetPort'] as int?) ?? 0,
            description: '${f['description'] ?? ''}',
          ));
        }
      }
      final scripts = o['scripts'];
      if (scripts is YamlList) {
        p.startupCommand = scripts
            .whereType<YamlMap>()
            .where((s) => s['send'] != null && s['expect'] == null)
            .map((s) => '${s['send']}')
            .join('\n');
      }
      if (item['id'] != null) tabbyIds['${item['id']}'] = p;
      if (o['jumpHost'] != null) jumpRefs[p] = '${o['jumpHost']}';
      result.add(p);
    }
    jumpRefs.forEach((p, ref) => p.jumpHostId = tabbyIds[ref]?.id);
    return result;
  }
}
