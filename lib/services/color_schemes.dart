import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// A terminal color scheme in Tabby's format (fg, bg, cursor, 16 ANSI colors).
class ColorScheme16 {
  ColorScheme16({
    required this.name,
    required this.foreground,
    required this.background,
    required this.cursor,
    required this.colors,
  });

  final String name;
  final Color foreground;
  final Color background;
  final Color cursor;
  final List<Color> colors;

  bool get isDark => background.computeLuminance() < 0.4;

  static Color _parse(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return Color(int.parse('ff$h', radix: 16));
  }

  factory ColorScheme16.fromJson(Map<String, dynamic> j) => ColorScheme16(
        name: j['name'],
        foreground: _parse(j['foreground']),
        background: _parse(j['background']),
        cursor: _parse(j['cursor']),
        colors: (j['colors'] as List).map((c) => _parse(c as String)).toList(),
      );

  TerminalTheme toTerminalTheme() => TerminalTheme(
        cursor: cursor,
        selection: foreground.withValues(alpha: 0.35),
        foreground: foreground,
        background: background,
        black: colors[0],
        red: colors[1],
        green: colors[2],
        yellow: colors[3],
        blue: colors[4],
        magenta: colors[5],
        cyan: colors[6],
        white: colors[7],
        brightBlack: colors[8],
        brightRed: colors[9],
        brightGreen: colors[10],
        brightYellow: colors[11],
        brightBlue: colors[12],
        brightMagenta: colors[13],
        brightCyan: colors[14],
        brightWhite: colors[15],
        searchHitBackground: const Color(0xFFFFFF2B),
        searchHitBackgroundCurrent: const Color(0xFF31FF26),
        searchHitForeground: const Color(0xFF000000),
      );
}

class ColorSchemes {
  ColorSchemes._();

  static List<ColorScheme16> all = [];

  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/color_schemes.json');
    all = (jsonDecode(raw) as List)
        .map((e) => ColorScheme16.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static ColorScheme16 byName(String? name) =>
      all.firstWhere((s) => s.name == name, orElse: () => all.first);
}
