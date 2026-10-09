import 'package:uuid/uuid.dart';

enum AuthType { auto, password, publicKey, keyboardInteractive }

enum ForwardType { local, remote, dynamic }

class PortForward {
  PortForward({
    required this.type,
    this.host = '127.0.0.1',
    required this.port,
    this.targetAddress = '127.0.0.1',
    this.targetPort = 0,
    this.description = '',
  });

  ForwardType type;
  String host;
  int port;
  String targetAddress;
  int targetPort;
  String description;

  String get label => switch (type) {
        ForwardType.local => 'L $host:$port → $targetAddress:$targetPort',
        ForwardType.remote => 'R $host:$port → $targetAddress:$targetPort',
        ForwardType.dynamic => 'D SOCKS $host:$port',
      };

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'host': host,
        'port': port,
        'targetAddress': targetAddress,
        'targetPort': targetPort,
        'description': description,
      };

  factory PortForward.fromJson(Map<String, dynamic> j) => PortForward(
        type: ForwardType.values.firstWhere((t) => t.name == j['type'],
            orElse: () => ForwardType.local),
        host: j['host'] ?? '127.0.0.1',
        port: j['port'] ?? 0,
        targetAddress: j['targetAddress'] ?? '127.0.0.1',
        targetPort: j['targetPort'] ?? 0,
        description: j['description'] ?? '',
      );
}

/// An SSH connection profile, modelled after Tabby's `SSHProfileOptions`.
/// Secrets (password) live in secure storage, keyed by [id].
class SshProfile {
  SshProfile({
    String? id,
    this.name = '',
    this.group = '',
    this.host = '',
    this.port = 22,
    this.user = 'root',
    this.auth = AuthType.auto,
    this.keyId,
    this.color,
    this.jumpHostId,
    this.startupCommand = '',
    this.keepaliveInterval = 30,
    this.readyTimeout = 20,
    this.term = 'xterm-256color',
    this.colorScheme,
    this.isFavorite = false,
    this.lastUsed,
    List<PortForward>? forwards,
  })  : id = id ?? const Uuid().v4(),
        forwards = forwards ?? [];

  final String id;
  String name;
  String group;
  String host;
  int port;
  String user;
  AuthType auth;
  String? keyId;
  int? color;
  String? jumpHostId;
  String startupCommand;
  int keepaliveInterval;
  int readyTimeout;
  String term;
  String? colorScheme;
  bool isFavorite;
  DateTime? lastUsed;
  List<PortForward> forwards;

  String get displayName => name.isNotEmpty ? name : '$user@$host';
  String get address => port == 22 ? '$user@$host' : '$user@$host:$port';

  SshProfile copy() => SshProfile.fromJson(toJson());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group': group,
        'host': host,
        'port': port,
        'user': user,
        'auth': auth.name,
        'keyId': keyId,
        'color': color,
        'jumpHostId': jumpHostId,
        'startupCommand': startupCommand,
        'keepaliveInterval': keepaliveInterval,
        'readyTimeout': readyTimeout,
        'term': term,
        'colorScheme': colorScheme,
        'isFavorite': isFavorite,
        'lastUsed': lastUsed?.toIso8601String(),
        'forwards': forwards.map((f) => f.toJson()).toList(),
      };

  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
        id: j['id'],
        name: j['name'] ?? '',
        group: j['group'] ?? '',
        host: j['host'] ?? '',
        port: j['port'] ?? 22,
        user: j['user'] ?? 'root',
        auth: AuthType.values.firstWhere((a) => a.name == j['auth'],
            orElse: () => AuthType.auto),
        keyId: j['keyId'],
        color: j['color'],
        jumpHostId: j['jumpHostId'],
        startupCommand: j['startupCommand'] ?? '',
        keepaliveInterval: j['keepaliveInterval'] ?? 30,
        readyTimeout: j['readyTimeout'] ?? 20,
        term: j['term'] ?? 'xterm-256color',
        colorScheme: j['colorScheme'],
        isFavorite: j['isFavorite'] ?? false,
        lastUsed: j['lastUsed'] != null ? DateTime.tryParse(j['lastUsed']) : null,
        forwards: ((j['forwards'] as List?) ?? [])
            .map((f) => PortForward.fromJson(Map<String, dynamic>.from(f)))
            .toList(),
      );

  /// Parses quick-connect strings like `user@host:2222` or `host`.
  static SshProfile? parseQuick(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    var user = 'root';
    var rest = s;
    final at = s.lastIndexOf('@');
    if (at > 0) {
      user = s.substring(0, at);
      rest = s.substring(at + 1);
    }
    var port = 22;
    var host = rest;
    final colon = rest.lastIndexOf(':');
    if (colon > 0 && !rest.contains(']') && rest.indexOf(':') == colon) {
      port = int.tryParse(rest.substring(colon + 1)) ?? 22;
      host = rest.substring(0, colon);
    } else if (rest.startsWith('[') && rest.contains(']:')) {
      final end = rest.indexOf(']:');
      host = rest.substring(1, end);
      port = int.tryParse(rest.substring(end + 2)) ?? 22;
    }
    if (host.isEmpty) return null;
    return SshProfile(host: host, port: port, user: user);
  }
}

/// A stored private key. The PEM and passphrase live in secure storage.
class StoredKey {
  StoredKey({String? id, required this.name, this.publicKey = '', this.type = ''})
      : id = id ?? const Uuid().v4();

  final String id;
  String name;
  String publicKey;
  String type;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'publicKey': publicKey, 'type': type};

  factory StoredKey.fromJson(Map<String, dynamic> j) => StoredKey(
        id: j['id'],
        name: j['name'] ?? 'key',
        publicKey: j['publicKey'] ?? '',
        type: j['type'] ?? '',
      );
}
