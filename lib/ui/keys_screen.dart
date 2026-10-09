import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/profile.dart';
import '../services/keys.dart';
import '../services/store.dart';
import 'dialogs.dart';

class KeysScreen extends StatelessWidget {
  const KeysScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Generate new Ed25519 key'),
            onTap: () => Navigator.pop(ctx, 'gen'),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Import from file'),
            subtitle: const Text('id_ed25519, id_rsa, id_ecdsa (OpenSSH / PEM)'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Paste private key'),
            onTap: () => Navigator.pop(ctx, 'paste'),
          ),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    final store = context.read<Store>();
    switch (choice) {
      case 'gen':
        final name = await promptText('Key name', label: 'Name', initial: 'nabby-ed25519');
        if (name == null || name.trim().isEmpty) return;
        final pass = await promptSecret(
          title: 'Passphrase (optional)',
          label: 'Passphrase',
          message: 'Leave empty for no passphrase.',
          offerRemember: false,
        );
        if (pass == null) return;
        final g = KeyTools.generateEd25519('${name.trim()}@nabby',
            passphrase: pass.value.isEmpty ? null : pass.value);
        final k = StoredKey(name: name.trim(), publicKey: g.publicLine, type: 'ssh-ed25519');
        await store.saveKey(k, pem: g.pem, passphrase: pass.value);
        toast('Key generated. Copy the public key to ~/.ssh/authorized_keys on your server.');
      case 'file':
        final f = await FilePicker.pickFile();
        if (f == null) return;
        final bytes = await f.readAsBytes();
        if (!context.mounted) return;
        await _import(context, utf8.decode(bytes, allowMalformed: true), f.name);
      case 'paste':
        if (!context.mounted) return;
        final pem = await _pasteDialog(context);
        if (pem == null || pem.trim().isEmpty || !context.mounted) return;
        await _import(context, pem, 'imported-key');
    }
  }

  Future<String?> _pasteDialog(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste private key'),
        content: TextField(
          controller: c,
          maxLines: 10,
          minLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 11),
          decoration: const InputDecoration(hintText: '-----BEGIN OPENSSH PRIVATE KEY-----'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Import')),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, String pem, String defaultName) async {
    final store = context.read<Store>();
    String? passphrase;
    if (KeyTools.isEncrypted(pem)) {
      final r = await promptSecret(
        title: 'Key passphrase',
        label: 'Passphrase',
        message: 'This key is encrypted. Tick Remember to store the passphrase securely.',
      );
      if (r == null) return;
      passphrase = r.value;
      try {
        final pub = KeyTools.validate(pem, passphrase: passphrase);
        final k = StoredKey(name: defaultName, publicKey: pub, type: pub.split(' ').first);
        await store.saveKey(k, pem: pem.trim(), passphrase: r.remember ? passphrase : null);
        toast('Key "$defaultName" imported');
      } catch (e) {
        toast('Could not import key: wrong passphrase or unsupported format');
      }
      return;
    }
    try {
      final pub = KeyTools.validate(pem);
      final k = StoredKey(name: defaultName, publicKey: pub, type: pub.split(' ').first);
      await store.saveKey(k, pem: pem.trim());
      toast('Key "$defaultName" imported');
    } catch (e) {
      toast('Could not import key: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('SSH keys')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add key'),
      ),
      body: store.keys.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No keys yet.\nGenerate a new key or import an existing one.\n'
                  'Private keys are kept in the Android Keystore.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: store.keys.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final k = store.keys[i];
                final used = store.profiles.where((p) => p.keyId == k.id).length;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.vpn_key),
                    title: Text(k.name),
                    subtitle: Text(
                      '${k.type} · used by $used host${used == 1 ? '' : 's'}\n${k.publicKey}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        switch (v) {
                          case 'copy':
                            await Clipboard.setData(ClipboardData(text: k.publicKey));
                            toast('Public key copied');
                          case 'share':
                            await SharePlus.instance.share(ShareParams(text: k.publicKey));
                          case 'rename':
                            final n = await promptText('Rename key', initial: k.name);
                            if (n != null && n.trim().isNotEmpty) {
                              await store.renameKey(k, n.trim());
                            }
                          case 'delete':
                            if (await confirm('Delete key',
                                'Delete "${k.name}"? Hosts using it will lose key auth.',
                                ok: 'Delete', destructive: true)) {
                              await store.deleteKey(k);
                            }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'copy', child: Text('Copy public key')),
                        PopupMenuItem(value: 'share', child: Text('Share public key')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: k.publicKey));
                      toast('Public key copied');
                    },
                  ),
                );
              },
            ),
    );
  }
}
