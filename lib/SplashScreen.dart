import 'package:flutter/material.dart';

import 'data/app_database.dart';
import 'data/session_store.dart';
import 'login_page.dart';
import 'tracking/arrival_notifications.dart';

/// The only splash the driver sees: Android's launch screen (same blue as
/// the top of the image) stays until this image is decoded, then the image
/// shows while the database opens.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _image = AssetImage('assets/images/backlogin.png');
  static const _minimumTime = Duration(seconds: 2);

  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Nothing is shown until the image is ready: Android's launch screen
    // (same blue) stays up meanwhile. Released in didChangeDependencies.
    WidgetsBinding.instance.deferFirstFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Draw the first frame only once the image is ready (no white flash).
    precacheImage(_image, context).whenComplete(
      WidgetsBinding.instance.allowFirstFrame,
    );
    _start();
  }

  Future<void> _start() async {
    await Future.wait([
      _openData(),
      Future<void>.delayed(_minimumTime),
    ]);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  Future<void> _openData() async {
    await AppDatabase.open();
    await SessionStore.instance.load();
    await ArrivalNotifications.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06539E),
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/backlogin.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
