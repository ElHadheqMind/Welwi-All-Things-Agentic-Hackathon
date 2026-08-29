import 'package:flutter_test/flutter_test.dart';
import 'package:welwi/main.dart';

void main() {
  testWidgets('Welwi app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const BenwApp());
  });
}
