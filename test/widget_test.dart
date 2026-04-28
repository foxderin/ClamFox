// Basic Flutter widget test for ClamFox.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:clamfox/main.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ClamFox app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ClamFoxApp());
    // Let async constructors (Process.run, SharedPreferences) settle.
    await tester.pump();

    // App brand and side-nav labels are present.
    expect(find.text('ClamFox'), findsOneWidget);
    expect(find.text('仪表板'), findsWidgets);
    expect(find.text('扫描'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('历史'), findsWidgets);
  });
}
