import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';
import 'package:example/main_full.dart';

void main() {
  testWidgets('SoundFont reader simple app smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SimpleSoundFontApp());
    expect(find.text('SoundFont Reader Simple Example'), findsOneWidget);
  });

  testWidgets('SoundFont reader full inspector smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundFontReaderDemoApp());
    expect(find.text('SoundFont Reader Inspector'), findsOneWidget);
  });
}
