import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

/// Persists profiles, keys and known hosts. Secrets go to the Android Keystore
/// backed secure storage; everything else to shared preferences.
class Store extends ChangeNotifier {
  Store(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage();

  final List<SshProfile> profiles = [];
  final List<StoredKey> keys = [];

  /// `host:port` -> `type SHA256:fingerprint`
  final Map<String, String> knownHosts = {};

  void _load() {
    List<dynamic> list(String k) {
      final raw = _prefs.getString(k);
      if (raw == null) return [];
      try {
        return jsonDecode(raw) as List;
      } catch (_) {
        return [];
      }
    }

    profiles.addAll(list('profiles')
        .map((e) => SshProfile.fromJson(Map<String, dynamic>.from(e))));
    keys.addAll(
        list('keys').map((e) => StoredKey.fromJson(Map<String, dynamic>.from(e))));
    final kh = _prefs.getString('knownHosts');
    if (kh != null) {
      knownHosts.addAll(Map<String, String>.from(jsonDecode(kh)));
    }
  }

  void _saveProfiles() {
    _prefs.setString(
        'profiles', jsonEncode(profiles.map((p) => p.toJson()).toList()));
    notifyListeners();
  }

  void _saveKeys() {
    _prefs.setString('keys', jsonEncode(keys.map((k) => k.toJson()).toList()));
    notifyListeners();
  }

  SshProfile? profileById(String? id) =>
      id == null ? null : profiles.where((p) => p.id == id).firstOrNull;

  StoredKey? keyById(String? id) =>
      id == null ? null : keys.where((k) => k.id == id).firstOrNull;

  List<String> get groups {
    final g = profiles.map((p) => p.group).where((g) => g.isNotEmpty).toSet().toList();
    g.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return g;
  }

  Future<void> saveProfile(SshProfile p, {String? password}) async {
    final i = profiles.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      profiles[i] = p;
    } else {
      profiles.add(p);
    }
    if (password != null) {
      if (password.isEmpty) {
        await _secure.delete(key: 'pw:${p.id}');
      } else {
        await _secure.write(key: 'pw:${p.id}', value: password);
      }
    }
    _saveProfiles();
  }

  void touchProfile(SshProfile p) {
    if (!profiles.any((e) => e.id == p.id)) return;
    p.lastUsed = DateTime.now();
    _saveProfiles();
  }

  Future<void> deleteProfile(SshProfile p) async {
    profiles.removeWhere((e) => e.id == p.id);
    for (final o in profiles) {
      if (o.jumpHostId == p.id) o.jumpHostId = null;
    }
    await _secure.delete(key: 'pw:${p.id}');
    _saveProfiles();
  }

  Future<String?> passwordFor(String profileId) =>
      _secure.read(key: 'pw:$profileId');

  Future<void> savePassword(String profileId, String password) =>
      _secure.write(key: 'pw:$profileId', value: password);

  Future<void> saveKey(StoredKey k, {required String pem, String? passphrase}) async {
    await _secure.write(key: 'key:${k.id}', value: pem);
    if (passphrase != null && passphrase.isNotEmpty) {
      await _secure.write(key: 'kp:${k.id}', value: passphrase);
    } else {
      await _secure.delete(key: 'kp:${k.id}');
    }
    final i = keys.indexWhere((e) => e.id == k.id);
    if (i >= 0) {
      keys[i] = k;
    } else {
      keys.add(k);
    }
    _saveKeys();
  }

  Future<void> renameKey(StoredKey k, String name) async {
    k.name = name;
    _saveKeys();
  }

  Future<String?> keyPem(String keyId) => _secure.read(key: 'key:$keyId');

  Future<String?> keyPassphrase(String keyId) => _secure.read(key: 'kp:$keyId');

  Future<void> deleteKey(StoredKey k) async {
    keys.removeWhere((e) => e.id == k.id);
    for (final p in profiles) {
      if (p.keyId == k.id) p.keyId = null;
    }
    await _secure.delete(key: 'key:${k.id}');
    await _secure.delete(key: 'kp:${k.id}');
    _saveKeys();
    _saveProfiles();
  }

  void setKnownHost(String hostPort, String value) {
    knownHosts[hostPort] = value;
    _prefs.setString('knownHosts', jsonEncode(knownHosts));
    notifyListeners();
  }

  void removeKnownHost(String hostPort) {
    knownHosts.remove(hostPort);
    _prefs.setString('knownHosts', jsonEncode(knownHosts));
    notifyListeners();
  }
}
