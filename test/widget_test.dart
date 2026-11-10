import 'package:flutter_test/flutter_test.dart';
import 'package:veyora/main.dart';

void main() {
  testWidgets('VeyoraApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VeyoraApp());
    // Pump duration to let splash screen transition complete
    await tester.pump(const Duration(seconds: 4));
  });
}
