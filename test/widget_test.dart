import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:android_elderly/main.dart';

void main() {
  testWidgets('settings page shows provided email', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          initialEmail: 'test@example.com',
          initialSmsPhoneNumber: '13800138000',
          initialDeviceName: '客厅手机',
          initialEmailServerSettings: EmailServerSettings.empty(),
        ),
      ),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('客厅手机'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('SMTP 邮件服务器'), findsOneWidget);
  });
}
