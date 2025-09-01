import 'package:flutter_test/flutter_test.dart';
import 'package:omega_intercom/main.dart';

void main() {
  testWidgets('App builds MapScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MapScreen), findsOneWidget);
  });
}
