import 'dart:ui';
import 'register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_flushbar/another_flushbar.dart';
import 'truck_selection_page.dart';
import 'data/session_store.dart';
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // true = password hidden, false = password visible
  bool _obscurePassword = true;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
   String? _usernameError;
  String? _passwordError;

  // Used to keep the Login button visible above the keyboard
  final GlobalKey _buttonsKey = GlobalKey();
  bool _keyboardWasOpen = false;

  void _onKeyboardChange(bool open) {
    if (open == _keyboardWasOpen) return;
    _keyboardWasOpen = open;
    if (!open) return;
    // Wait for the card to move up, then scroll the buttons into view.
    Future.delayed(const Duration(milliseconds: 300), () {
      final ctx = _buttonsKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

   @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
 
Future<void> _login() async {
  final username = _usernameController.text.trim();
  final password = _passwordController.text;

  setState(() {
    _usernameError =
        username.isEmpty ? 'Please enter your username' : null;
    _passwordError =
        password.isEmpty ? 'Please enter your password' : null;
  });

  if (username.isEmpty || password.isEmpty) {
    Flushbar(
      title: "Missing information",
      message: "Please enter your username and password.",
      icon: const Icon(
        Icons.warning_amber_rounded,
        color: Colors.white,
      ),
      backgroundColor: Colors.orange,
      borderRadius: BorderRadius.circular(12),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 3),
      flushbarPosition: FlushbarPosition.TOP,
    ).show(context);
  } else {
    // TODO: check the username and PIN with the API.
    await SessionStore.instance.login(username);
    if (!mounted) return;

    // A driver with a remembered truck goes straight to the deliveries.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const TruckSelectionPage(autoContinue: true),
      ),
    );
  }
}

   void _showMessage(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    _onKeyboardChange(keyboardOpen);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,

        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/backlogin.png'),
            fit: BoxFit.cover,
          ),
        ),

        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                // Smaller gap while the keyboard is open, so the whole
                // form (with the Login button) fits above it.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  height: keyboardOpen ? 110 : 200,
                ),

                // LOGIN CARD
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.80),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.65),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            // TITLE
                            const Text(
                              'Welcome Back',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF102A43),
                              ),
                            ),

                            const SizedBox(height: 3),

                            const Text(
                              'Please login to your account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF526D8A),
                              ),
                            ),

                            const SizedBox(height: 18),

                            // USERNAME
                            SizedBox(
                              height: 52,
                              child: TextField(
                                controller: _usernameController,
                                // Alphanumeric username: letters and digits
                                // only, keyboard with the number row and
                                // no autocorrect
                                keyboardType: TextInputType.visiblePassword,
                                autocorrect: false,
                                enableSuggestions: false,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[a-zA-Z0-9]'),
                                  ),
                                ],
                                textInputAction: TextInputAction.next,
                                 onChanged: (_) {
    if (_usernameError != null) {
      setState(() => _usernameError = null);
    }
  },
                                decoration: InputDecoration(
                                  hintText: 'Username',
                                   errorText: _usernameError,
                                  prefixIcon: const Icon(
                                    Icons.person_outline,
                                    color: Color(0xFF58708C),
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.92),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // PASSWORD (show / hide)
                            SizedBox(
                              height: 52,
                              child: TextField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                // Numeric password: number keyboard, digits only
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _login(),
                                  onChanged: (_) {
    if (_passwordError != null) {
      setState(() => _passwordError = null);
    }
  },
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                    errorText: _passwordError,
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFF58708C),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: const Color(0xFF58708C),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.92),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // BUTTONS
                            Row(
                              key: _buttonsKey,
                              children: [
                                // LOGIN
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed:_login ,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF0878E5),
                                        foregroundColor: Colors.white,
                                        elevation: 4,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Login',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 10),

                                // REGISTER
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: OutlinedButton(
                                      onPressed: () {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const RegisterPage()),
  );
},
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF0878E5),
                                        side: const BorderSide(
                                          color: Color(0xFF0878E5),
                                          width: 2,
                                        ),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Text(
                                        'Register',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            const Divider(
                              color: Color(0x55627094),
                              thickness: 1,
                              height: 1,
                            ),

                            const SizedBox(height: 15),

                            // SECURITY
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  size: 19,
                                  color: Color(0xFF58708C),
                                ),
                                SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    'Secure login. Your data is safe with us.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF58708C),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}