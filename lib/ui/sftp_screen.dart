import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/profile.dart';
import '../services/ssh_connector.dart';
import '../services/store.dart';
import 'dialogs.dart';

String formatSize(int? bytes) {
  if (bytes == null) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '$bytes B' : '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

String joinPath(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

String parentPath(String path) {
  if (path == '/' || path.isEmpty) return '/';
  final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  final i = trimmed.lastIndexOf('/');
  return i <= 0 ? '/' : trimmed.substring(0, i);
}

class Transfer extends ChangeNotifier {
  Transfer(this.name, this.upload, this.total);
  final String name;
  final bool upload;
  final int? total;
  int done = 0;
  bool finished = false;
  String? error;

  double? get progress => (total == null || total == 0) ? null : done / total!;

  void update(int d) {
    done = d;
    notifyListeners();
  }

  void finish([String? err]) {
    finished = true;
    error = err;
    notifyListeners();
  }
}

/// SFTP file browser, like Tabby's SFTP panel.
class SftpScreen extends StatefulWidget {
  const SftpScreen({super.key, required this.profile, this.client});

  final SshProfile profile;

  /// Reuses an existing terminal connection when given.
  final SSHClient? client;

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

enum _Sort { name, size, date }

class _SftpScreenState extends State<SftpScreen> {
  List<SSHClient> _ownClients = [];
  SftpClient? _sftp;
  String _path = '/';
  String _home = '/';
  List<SftpName> _items = [];
  bool _loading = true;
  String? _error;
  bool _showHidden = false;
  _Sort _sort = _Sort.name;
  final List<Transfer> _transfers = [];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _sftp?.close();
    for (final c in _ownClients.reversed) {
      c.close();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var client = widget.client;
      if (client == null) {
        final store = context.read<Store>();
        _ownClients = await SshConnector(store).connect(widget.profile);
        client = _ownClients.last;
        store.touchProfile(widget.profile);
      }
      _sftp = await client.sftp();
      _home = await _sftp!.absolute('.');
      await _open(_home);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _open(String path) async {
    final sftp = _sftp;
    if (sftp == null) return;
    setState(() => _loading = true);
    try {
      final items = await sftp.listdir(path);
      items.removeWhere((e) => e.filename == '.' || e.filename == '..');
      if (!mounted) return;
      setState(() {
        _path = path;
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      toast('Cannot open $path: ${_msg(e)}');
    }
  }

  String _msg(Object e) => e is SftpStatusError ? e.message : '$e';

  Future<void> _refresh() => _open(_path);

  List<SftpName> get _visible {
    final list = _items.where((e) => _showHidden || !e.filename.startsWith('.')).toList();
    int cmp(SftpName a, SftpName b) => switch (_sort) {
          _Sort.name => a.filename.toLowerCase().compareTo(b.filename.toLowerCase()),
          _Sort.size => (b.attr.size ?? 0).compareTo(a.attr.size ?? 0),
          _Sort.date => (b.attr.modifyTime ?? 0).compareTo(a.attr.modifyTime ?? 0),
        };
    list.sort((a, b) {
      final ad = _isDir(a), bd = _isDir(b);
      if (ad != bd) return ad ? -1 : 1;
      return cmp(a, b);
    });
    return list;
  }

  bool _isDir(SftpName e) => e.attr.isDirectory;

  Future<void> _tap(SftpName e) async {
    final full = joinPath(_path, e.filename);
    if (e.attr.isDirectory) return _open(full);
    if (e.attr.isSymbolicLink) {
      try {
        final st = await _sftp!.stat(full);
        if (st.isDirectory) return _open(full);
      } catch (_) {}
    }
    _fileActions(e);
  }

  Future<File> _downloadToTemp(SftpName e, {String? subdir}) async {
    final dir = await getTemporaryDirectory();
    final target = Directory('${dir.path}/${subdir ?? 'sftp'}');
    await target.create(recursive: true);
    final file = File('${target.path}/${e.filename}');
    final t = Transfer(e.filename, false, e.attr.size);
    setState(() => _transfers.add(t));
    final sink = file.openWrite();
    try {
      final remote = await _sftp!.open(joinPath(_path, e.filename));
      await remote.downloadTo(sink, onProgress: t.update);
      await remote.close();
      await sink.close();
      t.finish();
      return file;
    } catch (err) {
      await sink.close();
      t.finish(_msg(err));
      rethrow;
    }
  }

  Future<void> _download(SftpName e) async {
    try {
      final f = await _downloadToTemp(e);
      final uri = await FilePicker.saveFile(
        fileName: e.filename,
        bytes: await f.readAsBytes(),
      );
      if (uri != null) toast('Saved ${e.filename}');
    } catch (err) {
      toast('Download failed: ${_msg(err)}');
    }
  }

  Future<void> _share(SftpName e) async {
    try {
      final f = await _downloadToTemp(e);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
    } catch (err) {
      toast('Failed: ${_msg(err)}');
    }
  }

  Future<void> _edit(SftpName e) async {
    if ((e.attr.size ?? 0) > 2 * 1024 * 1024) {
      toast('File too large to edit here (max 2 MB)');
      return;
    }
    final path = joinPath(_path, e.filename);
    try {
      final f = await _sftp!.open(path);
      final bytes = await f.readBytes();
      await f.close();
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => _TextEditor(
            title: e.filename,
            initial: utf8.decode(bytes, allowMalformed: true),
            onSave: (text) async {
              final w = await _sftp!.open(path,
                  mode: SftpFileOpenMode.write |
                      SftpFileOpenMode.truncate |
                      SftpFileOpenMode.create);
              await w.writeBytes(Uint8List.fromList(utf8.encode(text)));
              await w.close();
            },
          ),
        ),
      );
      if (saved == true) _refresh();
    } catch (err) {
      toast('Cannot open file: ${_msg(err)}');
    }
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    for (final f in files) {
      final t = Transfer(f.name, true, await f.length());
      setState(() => _transfers.add(t));
      try {
        final remote = await _sftp!.open(
          joinPath(_path, f.name),
          mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write,
        );
        await remote.write(f.readAsByteStream(), onProgress: t.update).done;
        await remote.close();
        t.finish();
      } catch (err) {
        t.finish(_msg(err));
        toast('Upload of ${f.name} failed: ${_msg(err)}');
      }
    }
    _refresh();
  }

  Future<void> _mkdir() async {
    final name = await promptText('New folder', label: 'Name', ok: 'Create');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _sftp!.mkdir(joinPath(_path, name.trim()));
      _refresh();
    } catch (e) {
      toast('Failed: ${_msg(e)}');
    }
  }

  Future<void> _newFile() async {
    final name = await promptText('New file', label: 'Name', ok: 'Create');
    if (name == null || name.trim().isEmpty) return;
    try {
      final f = await _sftp!.open(joinPath(_path, name.trim()),
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.exclusive);
      await f.close();
      _refresh();
    } catch (e) {
      toast('Failed: ${_msg(e)}');
    }
  }

  Future<void> _rename(SftpName e) async {
    final name = await promptText('Rename', initial: e.filename, ok: 'Rename');
    if (name == null || name.trim().isEmpty || name == e.filename) return;
    try {
      final target = name.startsWith('/') ? name : joinPath(_path, name.trim());
      await _sftp!.rename(joinPath(_path, e.filename), target);
      _refresh();
    } catch (err) {
      toast('Failed: ${_msg(err)}');
    }
  }

  Future<void> _chmod(SftpName e) async {
    final current = (e.attr.mode?.value ?? 0) & 0x1FF;
    final v = await promptText('Permissions (octal)',
        initial: current.toRadixString(8).padLeft(3, '0'), ok: 'Apply');
    if (v == null) return;
    final n = int.tryParse(v.trim(), radix: 8);
    if (n == null || n > 0xFFF) {
      toast('Invalid mode');
      return;
    }
    try {
      final type = (e.attr.mode?.value ?? 0) & ~0xFFF;
      await _sftp!.setStat(
          joinPath(_path, e.filename), SftpFileAttrs(mode: SftpFileMode.value(type | n)));
      _refresh();
    } catch (err) {
      toast('Failed: ${_msg(err)}');
    }
  }

  Future<void> _deleteRecursive(String path) async {
    final items = await _sftp!.listdir(path);
    for (final i in items) {
      if (i.filename == '.' || i.filename == '..') continue;
      final p = joinPath(path, i.filename);
      if (i.attr.isDirectory) {
        await _deleteRecursive(p);
      } else {
        await _sftp!.remove(p);
      }
    }
    await _sftp!.rmdir(path);
  }

  Future<void> _delete(SftpName e) async {
    final dir = e.attr.isDirectory;
    if (!await confirm('Delete',
        'Delete ${dir ? 'folder' : 'file'} "${e.filename}"${dir ? ' and everything inside it' : ''}?',
        ok: 'Delete', destructive: true)) {
      return;
    }
    try {
      final p = joinPath(_path, e.filename);
      if (dir) {
        await _deleteRecursive(p);
      } else {
        await _sftp!.remove(p);
      }
      _refresh();
    } catch (err) {
      toast('Failed: ${_msg(err)}');
    }
  }

  void _fileActions(SftpName e) {
    final dir = e.attr.isDirectory;
    final full = joinPath(_path, e.filename);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(dir ? Icons.folder : Icons.insert_drive_file_outlined),
              title: Text(e.filename, overflow: TextOverflow.ellipsis),
              subtitle: Text('${e.longname.split(RegExp(r'\s+')).first}  ${formatSize(e.attr.size)}'),
            ),
            const Divider(),
            if (!dir) ...[
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  _edit(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download / save to phone'),
                onTap: () {
                  Navigator.pop(ctx);
                  _download(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open with / share'),
                onTap: () {
                  Navigator.pop(ctx);
                  _share(e);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename / move'),
              onTap: () {
                Navigator.pop(ctx);
                _rename(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Permissions'),
              onTap: () {
                Navigator.pop(ctx);
                _chmod(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy path'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: full));
                Navigator.pop(ctx);
                toast('Path copied');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(e);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _breadcrumbs() {
    final parts = _path.split('/').where((p) => p.isNotEmpty).toList();
    final crumbs = <Widget>[
      _crumb('/', '/'),
    ];
    var acc = '';
    for (final p in parts) {
      acc = '$acc/$p';
      crumbs.add(const Icon(Icons.chevron_right, size: 16));
      crumbs.add(_crumb(p, acc));
    }
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [Row(children: crumbs)],
      ),
    );
  }

  Widget _crumb(String label, String path) => InkWell(
        onTap: () => _open(path),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  fontWeight: path == _path ? FontWeight.bold : FontWeight.normal)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final activeTransfers = _transfers.where((t) => !t.finished).toList();
    return PopScope(
      canPop: _path == '/' || _sftp == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _open(parentPath(_path));
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close SFTP',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SFTP · ${widget.profile.displayName}', style: const TextStyle(fontSize: 16)),
            Text(widget.profile.address,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Home',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _open(_home),
            ),
            IconButton(
              tooltip: 'Go to path',
              icon: const Icon(Icons.drive_folder_upload_outlined),
              onPressed: () async {
                final p = await promptText('Go to path', initial: _path, ok: 'Go');
                if (p != null && p.trim().isNotEmpty) _open(p.trim());
              },
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'hidden':
                    setState(() => _showHidden = !_showHidden);
                  case 'name':
                    setState(() => _sort = _Sort.name);
                  case 'size':
                    setState(() => _sort = _Sort.size);
                  case 'date':
                    setState(() => _sort = _Sort.date);
                  case 'newfile':
                    _newFile();
                  case 'copy':
                    Clipboard.setData(ClipboardData(text: _path));
                    toast('Path copied');
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                    value: 'hidden', checked: _showHidden, child: const Text('Show hidden files')),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                    value: 'name', checked: _sort == _Sort.name, child: const Text('Sort by name')),
                CheckedPopupMenuItem(
                    value: 'size', checked: _sort == _Sort.size, child: const Text('Sort by size')),
                CheckedPopupMenuItem(
                    value: 'date', checked: _sort == _Sort.date, child: const Text('Sort by date')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'newfile', child: Text('New file')),
                const PopupMenuItem(value: 'copy', child: Text('Copy current path')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _breadcrumbs(),
          ),
        ),
        floatingActionButton: _sftp == null
            ? null
            : Column(mainAxisSize: MainAxisSize.min, children: [
                FloatingActionButton.small(
                  heroTag: 'mkdir',
                  tooltip: 'New folder',
                  onPressed: _mkdir,
                  child: const Icon(Icons.create_new_folder_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'upload',
                  onPressed: _upload,
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload'),
                ),
              ]),
        body: Column(children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          for (final t in activeTransfers)
            ListenableBuilder(
              listenable: t,
              builder: (_, _) => ListTile(
                dense: true,
                leading: Icon(t.upload ? Icons.upload : Icons.download, size: 20),
                title: Text(t.name, overflow: TextOverflow.ellipsis),
                subtitle: LinearProgressIndicator(value: t.progress),
                trailing: Text('${formatSize(t.done)}${t.total != null ? ' / ${formatSize(t.total)}' : ''}',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _connect, child: const Text('Retry')),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 140),
                      itemCount: visible.length + (_path == '/' ? 0 : 1),
                      itemBuilder: (ctx, i) {
                        if (_path != '/' && i == 0) {
                          return ListTile(
                            leading: const Icon(Icons.arrow_upward),
                            title: const Text('..'),
                            onTap: () => _open(parentPath(_path)),
                          );
                        }
                        final e = visible[i - (_path == '/' ? 0 : 1)];
                        final dir = e.attr.isDirectory;
                        final link = e.attr.isSymbolicLink;
                        final mtime = e.attr.modifyTime;
                        final date = mtime == null
                            ? ''
                            : DateTime.fromMillisecondsSinceEpoch(mtime * 1000)
                                .toString()
                                .substring(0, 16);
                        return ListTile(
                          leading: Icon(
                            dir
                                ? Icons.folder
                                : link
                                    ? Icons.link
                                    : _iconFor(e.filename),
                            color: dir ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text(e.filename, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              e.longname.split(RegExp(r'\s+')).first,
                              if (!dir) formatSize(e.attr.size),
                              date,
                            ].where((s) => s.isNotEmpty).join('  ·  '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => _tap(e),
                          onLongPress: () => _fileActions(e),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _fileActions(e),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' => Icons.image_outlined,
      'zip' || 'gz' || 'tar' || 'tgz' || 'xz' || 'bz2' || '7z' || 'rar' => Icons.archive_outlined,
      'sh' || 'py' || 'js' || 'ts' || 'dart' || 'go' || 'rs' || 'c' || 'cpp' || 'java' ||
      'php' || 'rb' => Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'ini' || 'conf' || 'env' || 'xml' => Icons.settings_applications_outlined,
      'log' || 'txt' || 'md' => Icons.article_outlined,
      'mp4' || 'mkv' || 'mov' || 'avi' => Icons.movie_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' => Icons.audiotrack_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

class _TextEditor extends StatefulWidget {
  const _TextEditor({required this.title, required this.initial, required this.onSave});

  final String title;
  final String initial;
  final Future<void> Function(String) onSave;

  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _c = TextEditingController(text: widget.initial);
  bool _dirty = false;
  bool _saving = false;
  bool _savedOnce = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_c.text);
      _dirty = false;
      _savedOnce = true;
      toast('Saved');
    } catch (e) {
      toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm('Discard changes?', 'You have unsaved changes.', ok: 'Discard',
            destructive: true)) {
          _dirty = false;
          if (context.mounted) Navigator.pop(context, _savedOnce);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => Navigator.maybePop(context, _savedOnce)),
          title: Text(widget.title + (_dirty ? ' •' : '')),
          actions: [
            IconButton(
              tooltip: 'Save',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: TextField(
          controller: _c,
          expands: true,
          maxLines: null,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 13),
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }
}
