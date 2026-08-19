import 'package:flutter_test/flutter_test.dart';
import 'package:nova/main.dart';

void main() {
  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(const NovaApp());
    expect(find.text('Nova'), findsOneWidget);
  });
}
