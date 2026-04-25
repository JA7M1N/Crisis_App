import 'package:flutter_test/flutter_test.dart';
import 'package:sankatmitra/main.dart';

void main() {
  testWidgets('CrisisLink smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // Note: This might fail in a real environment without Firebase mocking,
    // but we fix the name reference here.
    await tester.pumpWidget(const CrisisLinkApp());

    expect(find.text('CrisisLink'), findsOneWidget);
  });
}
