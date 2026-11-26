import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lapis_suites/main.dart';

void main() {
  testWidgets('LapisSuitesApp renders sign-in screen when no session saved', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const LapisSuitesApp());
    await tester.pumpAndSettle();
    expect(find.text('LAPIS SUITES'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
