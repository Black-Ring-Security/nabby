import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;

class GeneratedKey {
  GeneratedKey(this.pem, this.publicLine);
  final String pem;
  final String publicLine;
}

class KeyTools {
  /// Generates a new Ed25519 key pair in OpenSSH format.
  static GeneratedKey generateEd25519(String comment, {String? passphrase}) {
    final signing = ed25519.SigningKey.generate();
    final pair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(signing.verifyKey.asTypedList),
      Uint8List.fromList(signing.asTypedList),
      comment,
    );
    final pem = pair.toPem(passphrase: passphrase);
    return GeneratedKey(pem, publicLine(pair, comment));
  }

  static String publicLine(SSHKeyPair pair, [String comment = '']) {
    final blob = base64.encode(pair.toPublicKey().encode());
    return '${pair.type} $blob${comment.isNotEmpty ? ' $comment' : ''}';
  }

  /// Validates a private key and returns its public `authorized_keys` line.
  /// Throws if the key cannot be parsed or the passphrase is wrong.
  static String validate(String pem, {String? passphrase, String comment = ''}) {
    final pairs = SSHKeyPair.fromPem(pem.trim(), passphrase);
    if (pairs.isEmpty) throw const FormatException('No key found');
    return publicLine(pairs.first, comment);
  }

  static bool isEncrypted(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem.trim());
    } catch (_) {
      return false;
    }
  }
}
