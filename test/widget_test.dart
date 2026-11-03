import 'package:flutter_test/flutter_test.dart';
import 'package:my_third_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MoodAndScentApp());
    expect(find.byType(MoodAndScentApp), findsOneWidget);
  });
}
