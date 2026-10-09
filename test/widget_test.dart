import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:viralcut_mobile/app.dart';

void main() {
  testWidgets('app shell loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: HalchalApp()),
    );
    expect(find.byType(HalchalApp), findsOneWidget);
    // AuthNotifier._init guards secure-storage reads with a 5s timeout; let it
    // elapse so no timer is left pending when the test ends.
    await tester.pump(const Duration(seconds: 6));
  });
}
