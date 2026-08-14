import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('SoundFont reader app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SoundFontReaderDemoApp());
    expect(find.text('SoundFont Reader Inspector'), findsOneWidget);
  });
}
