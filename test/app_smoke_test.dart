import 'package:flutter_test/flutter_test.dart';
import 'package:van/main.dart';

void main() {
  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(const VanApp());
    expect(find.textContaining('Van'), findsOneWidget);
  });
}
