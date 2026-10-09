import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/color_schemes.dart';
import '../services/settings.dart';
import '../services/store.dart';
import '../services/tabby_import.dart';
import '../services/updates.dart';
import 'dialogs.dart';
import 'scheme_picker.dart';

const accentColors = [
  0xFF4E9AF1, 0xFF00B8D4, 0xFF26A69A, 0xFF66BB6A, 0xFFFFB300,
  0xFFFF7043, 0xFFEC407A, 0xFFAB47BC, 0xFF7E57C2,
];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(t.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1, color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _importTabby(BuildContext context) async {
    final store = context.read<Store>();
    final f = await FilePicker.pickFile();
    if (f == null) return;
    try {
      final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      final profiles = TabbyImport.parse(text);
      if (profiles.isEmpty) {
        toast('No SSH profiles found in that file');
        return;
      }
      var added = 0;
      for (final p in profiles) {
        final dup = store.profiles.any((e) =>
            e.host == p.host && e.port == p.port && e.user == p.user && e.name == p.name);
        if (dup) continue;
        await store.saveProfile(p);
        added++;
      }
      toast('Imported $added SSH profile${added == 1 ? '' : 's'} from Tabby. '
          'Passwords and keys must be added again.');
    } catch (e) {
      toast('Import failed: $e');
    }
  }

  Future<void> _export(BuildContext context) async {
    final store = context.read<Store>();
    final settings = context.read<AppSettings>();
    final data = {
      'app': 'nabby',
      'version': 1,
      'profiles': store.profiles.map((p) => p.toJson()).toList(),
      'knownHosts': store.knownHosts,
      'settings': settings.toJson(),
    };
    final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
    final uri = await FilePicker.saveFile(
      fileName: 'nabby-backup.json',
      bytes: bytes,
      mimeType: 'application/json',
    );
    if (uri != null) toast('Backup saved (without passwords and keys)');
  }

  Future<void> _restore(BuildContext context) async {
    final store = context.read<Store>();
    final f = await FilePicker.pickFile();
    if (f == null) return;
    try {
      final j = jsonDecode(utf8.decode(await f.readAsBytes())) as Map<String, dynamic>;
      if (j['app'] != 'nabby') throw const FormatException('Not a Nabby backup');
      var added = 0;
      for (final raw in (j['profiles'] as List? ?? [])) {
        final p = SshProfile.fromJson(Map<String, dynamic>.from(raw));
        if (store.profileById(p.id) != null) continue;
        await store.saveProfile(p);
        added++;
      }
      (j['knownHosts'] as Map?)?.forEach((k, v) {
        if (!store.knownHosts.containsKey(k)) store.setKnownHost('$k', '$v');
      });
      toast('Restored $added host${added == 1 ? '' : 's'}');
    } catch (e) {
      toast('Restore failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final store = context.watch<Store>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _header(context, 'Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.update((x) => x.themeMode = v.first),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in accentColors)
                GestureDetector(
                  onTap: () => s.update((x) => x.accentColor = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: s.accentColor == c
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
          ),
          ListTile(
            title: const Text('Terminal color scheme'),
            subtitle: Text('${s.colorScheme}  ·  ${ColorSchemes.all.length} available'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final name = await pickScheme(context, s.colorScheme);
              if (name != null) s.update((x) => x.colorScheme = name);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SchemePreview(scheme: ColorSchemes.byName(s.colorScheme)),
          ),
          ListTile(
            title: const Text('Font size'),
            subtitle: Slider(
              min: 6,
              max: 32,
              divisions: 26,
              value: s.fontSize.clamp(6, 32),
              label: '${s.fontSize.round()}',
              onChanged: (v) => s.update((x) => x.fontSize = v.roundToDouble()),
            ),
            trailing: Text('${s.fontSize.round()}'),
          ),
          ListTile(
            title: const Text('Font'),
            trailing: DropdownButton<String>(
              value: s.fontFamily,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'SourceCodePro', child: Text('Source Code Pro')),
                DropdownMenuItem(value: 'monospace', child: Text('System monospace')),
              ],
              onChanged: (v) => s.update((x) => x.fontFamily = v!),
            ),
          ),
          ListTile(
            title: const Text('Cursor'),
            trailing: DropdownButton<String>(
              value: s.cursor,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'block', child: Text('Block')),
                DropdownMenuItem(value: 'underline', child: Text('Underline')),
                DropdownMenuItem(value: 'bar', child: Text('Bar')),
              ],
              onChanged: (v) => s.update((x) => x.cursor = v!),
            ),
          ),
          _header(context, 'Terminal'),
          SwitchListTile(
            title: const Text('Extra keys bar'),
            subtitle: const Text('ESC, TAB, CTRL, ALT, arrows, F-keys'),
            value: s.showExtraKeys,
            onChanged: (v) => s.update((x) => x.showExtraKeys = v),
          ),
          SwitchListTile(
            title: const Text('Keep screen on in terminal'),
            value: s.keepScreenOn,
            onChanged: (v) => s.update((x) => x.keepScreenOn = v),
          ),
          SwitchListTile(
            title: const Text('Vibrate on bell'),
            value: s.vibrateOnBell,
            onChanged: (v) => s.update((x) => x.vibrateOnBell = v),
          ),
          SwitchListTile(
            title: const Text('Warn on multi-line paste'),
            value: s.warnOnMultilinePaste,
            onChanged: (v) => s.update((x) => x.warnOnMultilinePaste = v),
          ),
          SwitchListTile(
            title: const Text('Confirm before closing connected tabs'),
            value: s.confirmClose,
            onChanged: (v) => s.update((x) => x.confirmClose = v),
          ),
          ListTile(
            title: const Text('Scrollback lines'),
            trailing: DropdownButton<int>(
              value: s.scrollback,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1000, child: Text('1,000')),
                DropdownMenuItem(value: 5000, child: Text('5,000')),
                DropdownMenuItem(value: 10000, child: Text('10,000')),
                DropdownMenuItem(value: 25000, child: Text('25,000')),
                DropdownMenuItem(value: 50000, child: Text('50,000')),
              ],
              onChanged: (v) => s.update((x) => x.scrollback = v!),
            ),
          ),
          _header(context, 'Connection'),
          SwitchListTile(
            title: const Text('Stay connected in background'),
            subtitle: const Text('Shows a notification while sessions are open so Android keeps them alive'),
            value: s.backgroundService,
            onChanged: (v) => s.update((x) => x.backgroundService = v),
          ),
          ListTile(
            title: const Text('Known hosts'),
            subtitle: Text('${store.knownHosts.length} saved host key${store.knownHosts.length == 1 ? '' : 's'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const _KnownHostsScreen())),
          ),
          _header(context, 'Data'),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Import from Tabby'),
            subtitle: const Text('Pick config.yaml from Tabby desktop (~/.config/tabby/config.yaml)'),
            onTap: () => _importTabby(context),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('Export backup'),
            subtitle: const Text('Hosts, known hosts and settings as JSON (no secrets)'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore backup'),
            onTap: () => _restore(context),
          ),
          _header(context, 'About'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (ctx, snap) => ListTile(
              leading: const Icon(Icons.terminal),
              title: Text('Nabby ${snap.data?.version ?? ''}'),
              subtitle: const Text('SSH & SFTP client for Android, inspired by Tabby (tabby.sh).\n'
                  'Edit BY Black Ring Security'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates'),
            onTap: () => Updates.check(manual: true),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Open source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Nabby',
              applicationLegalese: 'Edit BY Black Ring Security\nMIT License',
            ),
          ),
        ],
      ),
    );
  }
}

class _KnownHostsScreen extends StatelessWidget {
  const _KnownHostsScreen();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final entries = store.knownHosts.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      appBar: AppBar(title: const Text('Known hosts')),
      body: entries.isEmpty
          ? const Center(child: Text('No saved host keys'))
          : ListView(
              children: [
                for (final e in entries)
                  ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value,
                        style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm('Forget host key',
                            'Forget the saved key for ${e.key}? You will be asked to verify it next time.',
                            ok: 'Forget')) {
                          store.removeKnownHost(e.key);
                        }
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
