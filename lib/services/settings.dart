import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

/// Global app settings, mirroring the relevant parts of Tabby's terminal config.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _apply(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  static const _key = 'settings';
  final SharedPreferences _prefs;

  ThemeMode themeMode = ThemeMode.dark;
  String colorScheme = 'Tabby Default';
  double fontSize = 13;
  String fontFamily = 'SourceCodePro';
  String cursor = 'block';
  int scrollback = 10000;
  bool keepScreenOn = true;
  bool showExtraKeys = true;
  bool vibrateOnBell = true;
  bool warnOnMultilinePaste = true;
  bool backgroundService = true;
  bool confirmClose = true;
  int accentColor = 0xFF4E9AF1;

  TerminalCursorType get cursorType => switch (cursor) {
        'underline' => TerminalCursorType.underline,
        'bar' => TerminalCursorType.verticalBar,
        _ => TerminalCursorType.block,
      };

  void _apply(Map<String, dynamic> j) {
    themeMode = ThemeMode.values.firstWhere((m) => m.name == j['themeMode'],
        orElse: () => ThemeMode.dark);
    colorScheme = j['colorScheme'] ?? colorScheme;
    fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
    fontFamily = j['fontFamily'] ?? fontFamily;
    cursor = j['cursor'] ?? cursor;
    scrollback = j['scrollback'] ?? scrollback;
    keepScreenOn = j['keepScreenOn'] ?? keepScreenOn;
    showExtraKeys = j['showExtraKeys'] ?? showExtraKeys;
    vibrateOnBell = j['vibrateOnBell'] ?? vibrateOnBell;
    warnOnMultilinePaste = j['warnOnMultilinePaste'] ?? warnOnMultilinePaste;
    backgroundService = j['backgroundService'] ?? backgroundService;
    confirmClose = j['confirmClose'] ?? confirmClose;
    accentColor = j['accentColor'] ?? accentColor;
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'colorScheme': colorScheme,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'cursor': cursor,
        'scrollback': scrollback,
        'keepScreenOn': keepScreenOn,
        'showExtraKeys': showExtraKeys,
        'vibrateOnBell': vibrateOnBell,
        'warnOnMultilinePaste': warnOnMultilinePaste,
        'backgroundService': backgroundService,
        'confirmClose': confirmClose,
        'accentColor': accentColor,
      };

  void update(void Function(AppSettings s) change) {
    change(this);
    _prefs.setString(_key, jsonEncode(toJson()));
    notifyListeners();
  }
}
