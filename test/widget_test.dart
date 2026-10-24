import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinji/app/xinji_app.dart';
import 'package:xinji/features/records/state/records_controller.dart';
import 'package:xinji/features/settings/state/settings_controller.dart';

void main() {
  testWidgets('薪迹应用可以正常构建并显示底部导航', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsController()),
          ChangeNotifierProvider(create: (_) => RecordsController()),
        ],
        child: const XinjiApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Streak 风格底栏（默认）：无文字标签，验证三个图标存在
    expect(find.byIcon(LucideIcons.house), findsOneWidget);
    expect(find.byIcon(LucideIcons.chartColumn), findsOneWidget);
    expect(find.byIcon(LucideIcons.settings), findsOneWidget);
    expect(find.text('今日收入'), findsOneWidget);
    expect(find.text('上班打卡'), findsOneWidget);
    expect(find.text('下班打卡'), findsOneWidget);
    expect(find.text('今日打卡'), findsOneWidget);
  });

  testWidgets('底栏显示文字标签偏好：开启后显示 今日/统计/设置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    late SettingsController settings;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsController()),
          ChangeNotifierProvider(create: (_) => RecordsController()),
        ],
        child: Builder(
          builder: (context) {
            settings = context.read<SettingsController>();
            return const XinjiApp();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 默认仅图标：底栏无「统计/设置」文字（今日页 AppBar 有「今日」）
    expect(find.text('统计'), findsNothing);
    expect(find.text('设置'), findsNothing);
    expect(find.text('今日'), findsOneWidget);

    // 开启文字标签：底栏立即显示标签
    settings.setNavBarLabels(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('今日'), findsNWidgets(2)); // AppBar + 底栏
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
