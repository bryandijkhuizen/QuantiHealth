import 'package:flutter_test/flutter_test.dart';
import 'package:quantivita/app.dart';

void main() {
  testWidgets('starts with Apple-only auth', (tester) async {
    await tester.pumpWidget(const QuantivitaApp());

    expect(find.text('Quantivita'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Register on this device'), findsNothing);
  });
}
