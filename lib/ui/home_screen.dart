import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/session.dart';
import '../services/store.dart';
import 'dialogs.dart';
import 'keys_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';
import 'sftp_screen.dart';
import 'terminal_screen.dart';

const profileColors = [
  0xFF4E9AF1, 0xFF5BC0BE, 0xFF7BD389, 0xFFF4D35E, 0xFFF79D65,
  0xFFEE6C4D, 0xFFE56B9A, 0xFFB388EB, 0xFF8D99AE,
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final Set<String> _collapsed = {};

  void _connect(SshProfile p) {
    context.read<SessionManager>().open(p);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TerminalScreen()));
  }

  void _openSftp(SshProfile p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SftpScreen(profile: p)));
  }

  Future<void> _edit([SshProfile? p]) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileEditScreen(profile: p)));
  }

  void _quickConnect() {
    final p = SshProfile.parseQuick(_search.text);
    if (p == null) return;
    _connect(p);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final sessions = context.watch<SessionManager>();
    final q = _search.text.trim().toLowerCase();
    final looksLikeQuick = q.contains('@') || RegExp(r'^[\w.-]+(:\d+)?$').hasMatch(q);

    final filtered = store.profiles.where((p) {
      if (q.isEmpty) return true;
      return p.displayName.toLowerCase().contains(q) ||
          p.host.toLowerCase().contains(q) ||
          p.user.toLowerCase().contains(q) ||
          p.group.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

    final sections = <String, List<SshProfile>>{};
    if (q.isEmpty) {
      final favs = filtered.where((p) => p.isFavorite).toList();
      if (favs.isNotEmpty) sections['★ Favorites'] = favs;
      final recent = filtered.where((p) => p.lastUsed != null).toList()
        ..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
      if (recent.length > 1) sections['Recent'] = recent.take(4).toList();
    }
    for (final p in filtered) {
      sections.putIfAbsent(p.group.isEmpty ? 'Ungrouped' : p.group, () => []).add(p);
    }
    if (sections.containsKey('Ungrouped')) {
      final u = sections.remove('Ungrouped')!;
      sections['Ungrouped'] = u;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.terminal, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nabby', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Edit BY Black Ring Security',
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.5,
                    color: Theme.of(context).colorScheme.outline)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'SSH keys',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const KeysScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('New host'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _quickConnect(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search hosts or quick connect user@host:port',
                suffixIcon: q.isEmpty
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (looksLikeQuick)
                          IconButton(
                            tooltip: 'Quick connect',
                            icon: const Icon(Icons.bolt),
                            onPressed: _quickConnect,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_search.clear),
                        ),
                      ]),
              ),
            ),
          ),
          if (sessions.sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.tab),
                  title: Text('${sessions.sessions.length} open tab'
                      '${sessions.sessions.length == 1 ? '' : 's'}'),
                  subtitle: Text('${sessions.connectedCount} connected'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TerminalScreen())),
                ),
              ),
            ),
          Expanded(
            child: store.profiles.isEmpty
                ? _empty(context)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                    children: [
                      for (final entry in sections.entries) ...[
                        InkWell(
                          onTap: () => setState(() => _collapsed.contains(entry.key)
                              ? _collapsed.remove(entry.key)
                              : _collapsed.add(entry.key)),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                            child: Row(children: [
                              Icon(
                                _collapsed.contains(entry.key)
                                    ? Icons.chevron_right
                                    : Icons.expand_more,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(entry.key.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      letterSpacing: 1,
                                      color: Theme.of(context).colorScheme.outline)),
                              const SizedBox(width: 6),
                              Text('${entry.value.length}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.outline)),
                            ]),
                          ),
                        ),
                        if (!_collapsed.contains(entry.key))
                          for (final p in entry.value)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _ProfileTile(
                                profile: p,
                                onConnect: () => _connect(p),
                                onSftp: () => _openSftp(p),
                                onEdit: () => _edit(p),
                              ),
                            ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.dns_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('No hosts yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Add a host, type user@host above to quick connect,\n'
              'or import your Tabby config from Settings.',
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.onConnect,
    required this.onSftp,
    required this.onEdit,
  });

  final SshProfile profile;
  final VoidCallback onConnect;
  final VoidCallback onSftp;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final color = Color(profile.color ?? Theme.of(context).colorScheme.primary.toARGB32());
    final jump = store.profileById(profile.jumpHostId);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onConnect,
        onLongPress: onEdit,
        child: Row(children: [
          Container(width: 4, height: 60, color: color),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Text(
              profile.displayName.isEmpty ? '?' : profile.displayName[0].toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(profile.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (profile.isFavorite)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    profile.address,
                    if (jump != null) 'via ${jump.displayName}',
                    if (profile.forwards.isNotEmpty) '${profile.forwards.length} fwd',
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'SFTP',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: onSftp,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'connect':
                  onConnect();
                case 'sftp':
                  onSftp();
                case 'edit':
                  onEdit();
                case 'fav':
                  profile.isFavorite = !profile.isFavorite;
                  await store.saveProfile(profile);
                case 'dup':
                  final c = profile.copy();
                  final dup = SshProfile.fromJson({
                    ...c.toJson(),
                    'id': null,
                    'name': '${profile.displayName} (copy)',
                    'lastUsed': null,
                  });
                  await store.saveProfile(dup);
                case 'delete':
                  if (await confirm('Delete host', 'Delete "${profile.displayName}"?',
                      ok: 'Delete', destructive: true)) {
                    await store.deleteProfile(profile);
                  }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'connect', child: Text('Connect')),
              const PopupMenuItem(value: 'sftp', child: Text('Open SFTP')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                  value: 'fav',
                  child: Text(profile.isFavorite ? 'Remove favorite' : 'Add to favorites')),
              const PopupMenuItem(value: 'dup', child: Text('Duplicate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }
}
