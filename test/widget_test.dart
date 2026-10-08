import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:truckg/SplashScreen.dart';
import 'package:truckg/data/app_database.dart';
import 'package:truckg/login_page.dart';
import 'package:truckg/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi; // desktop SQLite for tests
  });
  tearDown(AppDatabase.close);

  testWidgets('starts on the splash image, then shows the login',
      (tester) async {
    await tester.runAsync(() async {
      final path = '${await databaseFactory.getDatabasesPath()}/truckgo.db';
      await databaseFactory.deleteDatabase(path);
    });

    await tester.pumpWidget(const MyApp());
    // Let the image load and the database open (real async work)
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    // After the minimum splash time (test clock), the login replaces it
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });
}
