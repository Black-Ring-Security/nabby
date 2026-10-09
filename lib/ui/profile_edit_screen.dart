import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/color_schemes.dart';
import '../services/store.dart';
import 'home_screen.dart' show profileColors;
import 'keys_screen.dart';
import 'scheme_picker.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key, this.profile});

  final SshProfile? profile;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final SshProfile p = widget.profile?.copy() ?? SshProfile();
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: p.name);
  late final _group = TextEditingController(text: p.group);
  late final _host = TextEditingController(text: p.host);
  late final _port = TextEditingController(text: '${p.port}');
  late final _user = TextEditingController(text: p.user);
  final _password = TextEditingController();
  late final _startup = TextEditingController(text: p.startupCommand);
  late final _keepalive = TextEditingController(text: '${p.keepaliveInterval}');
  late final _timeout = TextEditingController(text: '${p.readyTimeout}');
  late final _term = TextEditingController(text: p.term);
  bool _hasStoredPassword = false;
  bool _passwordChanged = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    if (widget.profile != null) {
      context.read<Store>().passwordFor(p.id).then((v) {
        if (mounted) setState(() => _hasStoredPassword = v != null && v.isNotEmpty);
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    p
      ..name = _name.text.trim()
      ..group = _group.text.trim()
      ..host = _host.text.trim()
      ..port = int.tryParse(_port.text) ?? 22
      ..user = _user.text.trim()
      ..startupCommand = _startup.text
      ..keepaliveInterval = int.tryParse(_keepalive.text) ?? 30
      ..readyTimeout = int.tryParse(_timeout.text) ?? 20
      ..term = _term.text.trim().isEmpty ? 'xterm-256color' : _term.text.trim();
    await context
        .read<Store>()
        .saveProfile(p, password: _passwordChanged ? _password.text : null);
    if (mounted) Navigator.pop(context);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
        child: Text(title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1, color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final jumpCandidates = store.profiles.where((o) => o.id != p.id).toList();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'New host' : 'Edit host'),
        actions: [
          TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('Save')),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
          children: [
            _section('Connection'),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            gap,
            Row(children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _host,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Host'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return (n == null || n < 1 || n > 65535) ? '1-65535' : null;
                  },
                ),
              ),
            ]),
            gap,
            TextFormField(
              controller: _user,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            gap,
            TextFormField(
              controller: _group,
              decoration: InputDecoration(
                labelText: 'Group (optional)',
                suffixIcon: store.groups.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (g) => setState(() => _group.text = g),
                        itemBuilder: (_) => [
                          for (final g in store.groups) PopupMenuItem(value: g, child: Text(g)),
                        ],
                      ),
              ),
            ),
            _section('Authentication'),
            SegmentedButton<AuthType>(
              segments: const [
                ButtonSegment(value: AuthType.auto, label: Text('Auto')),
                ButtonSegment(value: AuthType.password, label: Text('Password')),
                ButtonSegment(value: AuthType.publicKey, label: Text('Key')),
                ButtonSegment(value: AuthType.keyboardInteractive, label: Text('Interactive')),
              ],
              showSelectedIcon: false,
              selected: {p.auth},
              onSelectionChanged: (s) => setState(() => p.auth = s.first),
            ),
            gap,
            if (p.auth != AuthType.publicKey) ...[
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) => _passwordChanged = true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _hasStoredPassword
                      ? 'Saved securely. Leave empty to keep, type to replace.'
                      : 'Optional. Stored in Android Keystore. Asked on connect if empty.',
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_hasStoredPassword)
                      IconButton(
                        tooltip: 'Forget saved password',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          _password.clear();
                          _passwordChanged = true;
                          _hasStoredPassword = false;
                        }),
                      ),
                    IconButton(
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ]),
                ),
              ),
              gap,
            ],
            if (p.auth == AuthType.auto || p.auth == AuthType.publicKey)
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: store.keyById(p.keyId)?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Private key'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final k in store.keys)
                        DropdownMenuItem(value: k.id, child: Text('${k.name}  (${k.type})')),
                    ],
                    onChanged: (v) => setState(() => p.keyId = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Manage keys',
                  icon: const Icon(Icons.vpn_key_outlined),
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const KeysScreen())),
                ),
              ]),
            _section('Jump host & forwarding'),
            DropdownButtonFormField<String?>(
              initialValue: store.profileById(p.jumpHostId)?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Jump host (ProxyJump)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None (direct)')),
                for (final o in jumpCandidates)
                  DropdownMenuItem(value: o.id, child: Text('${o.displayName}  ${o.address}')),
              ],
              onChanged: (v) => setState(() => p.jumpHostId = v),
            ),
            gap,
            for (final f in p.forwards)
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(f.label),
                  subtitle: f.description.isEmpty ? null : Text(f.description),
                  onTap: () async {
                    final edited = await editForward(context, f);
                    if (edited != null) setState(() {});
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => p.forwards.remove(f)),
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final f = await editForward(context, null);
                if (f != null) setState(() => p.forwards.add(f));
              },
              icon: const Icon(Icons.add),
              label: const Text('Add port forward'),
            ),
            _section('Terminal'),
            TextFormField(
              controller: _startup,
              minLines: 1,
              maxLines: 5,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Startup commands',
                helperText: 'Sent after login, one per line',
              ),
            ),
            gap,
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Color scheme'),
              subtitle: Text(p.colorScheme ?? 'Use global default'),
              trailing: p.colorScheme == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => p.colorScheme = null),
                    ),
              onTap: () async {
                final s = await pickScheme(context, p.colorScheme);
                if (s != null) setState(() => p.colorScheme = s);
              },
            ),
            if (p.colorScheme != null)
              SchemePreview(scheme: ColorSchemes.byName(p.colorScheme)),
            gap,
            const Text('Tag color'),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in profileColors)
                GestureDetector(
                  onTap: () => setState(() => p.color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: p.color == c ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                  ),
                ),
            ]),
            _section('Advanced'),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _keepalive,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Keepalive (s, 0=off)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _timeout,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Timeout (s)'),
                ),
              ),
            ]),
            gap,
            TextFormField(
              controller: _term,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'TERM'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<PortForward?> editForward(BuildContext context, PortForward? existing) {
  final f = existing ??
      PortForward(type: ForwardType.local, port: 8080, targetAddress: '127.0.0.1', targetPort: 80);
  var type = f.type;
  final host = TextEditingController(text: f.host);
  final port = TextEditingController(text: '${f.port}');
  final tHost = TextEditingController(text: f.targetAddress);
  final tPort = TextEditingController(text: '${f.targetPort}');
  final desc = TextEditingController(text: f.description);
  return showDialog<PortForward>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Port forward'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<ForwardType>(
              segments: const [
                ButtonSegment(value: ForwardType.local, label: Text('Local')),
                ButtonSegment(value: ForwardType.remote, label: Text('Remote')),
                ButtonSegment(value: ForwardType.dynamic, label: Text('SOCKS')),
              ],
              showSelectedIcon: false,
              selected: {type},
              onSelectionChanged: (s) => setState(() => type = s.first),
            ),
            const SizedBox(height: 12),
            Text(
              switch (type) {
                ForwardType.local => 'Listen on this phone, connect from the server.',
                ForwardType.remote => 'Listen on the server, connect from this phone.',
                ForwardType.dynamic => 'SOCKS5 proxy on this phone through the server.',
              },
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  flex: 2,
                  child: TextField(
                      controller: host,
                      decoration: const InputDecoration(labelText: 'Bind address'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: port,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Port'))),
            ]),
            if (type != ForwardType.dynamic) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    flex: 2,
                    child: TextField(
                        controller: tHost,
                        decoration: const InputDecoration(labelText: 'Target host'))),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: tPort,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port'))),
              ]),
            ],
            const SizedBox(height: 12),
            TextField(
                controller: desc, decoration: const InputDecoration(labelText: 'Description')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              f
                ..type = type
                ..host = host.text.trim()
                ..port = int.tryParse(port.text) ?? 0
                ..targetAddress = tHost.text.trim()
                ..targetPort = int.tryParse(tPort.text) ?? 0
                ..description = desc.text;
              Navigator.pop(ctx, f);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
