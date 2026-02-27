import 'package:flutter_test/flutter_test.dart';
import 'package:piper/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PiperApp());
    expect(find.byType(PiperApp), findsOneWidget);
  });
}
