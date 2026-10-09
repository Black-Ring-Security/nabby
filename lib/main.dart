import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/color_schemes.dart';
import 'services/keepalive.dart';
import 'services/session.dart';
import 'services/settings.dart';
import 'services/store.dart';
import 'services/updates.dart';
import 'ui/dialogs.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Source Code Pro'], await rootBundle.loadString('assets/licenses/OFL-SourceCodePro.txt'));
    yield LicenseEntryWithLineBreaks(
        ['Tabby', 'Tabby color schemes'], await rootBundle.loadString('assets/licenses/MIT-Tabby.txt'));
  });
  final prefs = await SharedPreferences.getInstance();
  await ColorSchemes.load();
  final settings = AppSettings(prefs);
  final store = Store(prefs);
  final sessions = SessionManager(store, settings);
  sessions.addListener(() => BackgroundKeepAlive.update(sessions.connectedCount,
      enabled: settings.backgroundService));
  BackgroundKeepAlive.init(onDisconnectAll: sessions.closeAll);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: store),
      ChangeNotifierProvider.value(value: sessions),
    ],
    child: const NabbyApp(),
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) => Updates.check());
}

class NabbyApp extends StatelessWidget {
  const NabbyApp({super.key});

  static ThemeData _theme(Brightness b, Color accent) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
      primary: accent,
      surface: dark ? const Color(0xFF151B22) : const Color(0xFFF6F8FA),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0F1419) : const Color(0xFFF6F8FA),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF151B22) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: dark ? const Color(0xFF1A222B) : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
          color: dark ? Colors.white10 : Colors.black12, space: 1, thickness: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final accent = Color(s.accentColor);
    return MaterialApp(
      title: 'Nabby',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      themeMode: s.themeMode,
      theme: _theme(Brightness.light, accent),
      darkTheme: _theme(Brightness.dark, accent),
      home: const HomeScreen(),
    );
  }
}
