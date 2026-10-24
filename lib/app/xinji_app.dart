import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:xinji/app/home_shell.dart';
import 'package:xinji/app/theme/app_theme.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

class XinjiApp extends StatelessWidget {
  const XinjiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: '薪迹',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.accent),
      darkTheme: AppTheme.dark(settings.accent, settings.oledBlack),
      themeMode: settings.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeShell(),
    );
  }
}
