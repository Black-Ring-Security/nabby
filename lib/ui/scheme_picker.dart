import 'package:flutter/material.dart';

import '../services/color_schemes.dart';

/// A small fake prompt rendered in the scheme's colors.
class SchemePreview extends StatelessWidget {
  const SchemePreview({super.key, required this.scheme, this.compact = false});

  final ColorScheme16 scheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = scheme.colors;
    TextSpan t(String s, Color col) => TextSpan(text: s, style: TextStyle(color: col));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontFamily: 'SourceCodePro', fontSize: 12),
            children: [
              t('admin', c[2]),
              t('@', scheme.foreground),
              t('server', c[4]),
              t(':', scheme.foreground),
              t('~/app', c[6]),
              t(' \$ ', scheme.foreground),
              t('ls ', scheme.foreground),
              t('-la', c[3]),
              if (!compact) ...[
                t('\ndrwxr-xr-x ', scheme.foreground),
                t('src', c[12]),
                t('  ', scheme.foreground),
                t('run.sh', c[10]),
                t('  ', scheme.foreground),
                t('error.log', c[1]),
                t('  ', scheme.foreground),
                t('README', c[5]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          for (final col in c)
            Expanded(child: Container(height: compact ? 6 : 10, color: col)),
        ]),
      ]),
    );
  }
}

Future<String?> pickScheme(BuildContext context, String? current) {
  return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _SchemePickerScreen(current: current)));
}

class _SchemePickerScreen extends StatefulWidget {
  const _SchemePickerScreen({this.current});

  final String? current;

  @override
  State<_SchemePickerScreen> createState() => _SchemePickerScreenState();
}

class _SchemePickerScreenState extends State<_SchemePickerScreen> {
  String _q = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final list = ColorSchemes.all.where((s) {
      if (_q.isNotEmpty && !s.name.toLowerCase().contains(_q)) return false;
      if (_filter == 'dark' && !s.isDark) return false;
      if (_filter == 'light' && s.isDark) return false;
      return true;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Color schemes (${list.length})')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Search schemes'),
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'dark', label: Text('Dark')),
              ButtonSegment(value: 'light', label: Text('Light')),
            ],
            showSelectedIcon: false,
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final s = list[i];
              final selected = s.name == widget.current;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, s.name),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, left: 2),
                      child: Row(children: [
                        if (selected)
                          Icon(Icons.check_circle,
                              size: 16, color: Theme.of(context).colorScheme.primary),
                        if (selected) const SizedBox(width: 6),
                        Text(s.name,
                            style: TextStyle(
                                fontWeight: selected ? FontWeight.bold : FontWeight.w500)),
                      ]),
                    ),
                    SchemePreview(scheme: s, compact: true),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
