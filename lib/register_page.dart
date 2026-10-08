import 'dart:ui';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _countryController = TextEditingController();
  final _plateController = TextEditingController();
  final _phoneCodeController = TextEditingController();
  final _phoneController = TextEditingController();

  Country? _selectedCountry;
  Country? _selectedPhoneCountry;

  // If the user picks the phone code himself, we stop auto-filling it
  bool _phoneCodeChosenManually = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _countryController.dispose();
    _plateController.dispose();
    _phoneCodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // COUNTRY PICKERS (searchable list)
  // ---------------------------------------------------------------

  CountryListThemeData _pickerTheme() {
    return CountryListThemeData(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      bottomSheetHeight: MediaQuery.of(context).size.height * 0.75,
      inputDecoration: InputDecoration(
        hintText: 'Search',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  void _setPhoneCountry(Country country) {
    _selectedPhoneCountry = country;
    _phoneCodeController.text = '${country.flagEmoji}  +${country.phoneCode}';
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      countryListTheme: _pickerTheme(),
      onSelect: (country) {
        setState(() {
          _selectedCountry = country;
          _countryController.text = '${country.flagEmoji}  ${country.name}';

          // Fill the phone code automatically with the same country
          if (!_phoneCodeChosenManually) {
            _setPhoneCountry(country);
          }
        });
      },
    );
  }

  void _pickPhoneCode() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      countryListTheme: _pickerTheme(),
      onSelect: (country) {
        setState(() {
          _phoneCodeChosenManually = true;
          _setPhoneCountry(country);
        });
      },
    );
  }

  // ---------------------------------------------------------------
  // VALIDATION + REGISTER
  // ---------------------------------------------------------------

  String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) return message;
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    if (value.length < 6) return 'Phone number is too short';
    return null;
  }

  void _register() {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    // All fields are valid: send this data to your server here
    final data = {
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'country': _selectedCountry?.name,
      'plateNumber': _plateController.text.trim().toUpperCase(),
      'phone':
          '+${_selectedPhoneCountry?.phoneCode}${_phoneController.text.trim()}',
    };
    debugPrint(data.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registration data is valid'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------
  // SHARED FIELD STYLE
  // ---------------------------------------------------------------

  InputDecoration _decoration({
    required String hint,
    IconData? icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon:
          icon == null ? null : Icon(icon, color: const Color(0xFF58708C)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(0.92),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(
        vertical: 14,
        horizontal: icon == null ? 12 : 0,
      ),
    );
  }

  static const _arrow = Icon(
    Icons.arrow_drop_down,
    color: Color(0xFF58708C),
  );

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B57A1), Color(0xFF063470)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Truck logo
                Image.asset(
                  'assets/images/truck_logo.png',
                  height: 100,
                ),

                const SizedBox(height: 20),

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
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            children: [
                              const Text(
                                'Create Account',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF102A43),
                                ),
                              ),

                              const SizedBox(height: 3),

                              const Text(
                                'Fill in your details to register',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF526D8A),
                                ),
                              ),

                              const SizedBox(height: 18),

                              // FIRST NAME
                              TextFormField(
                                controller: _firstNameController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                validator: (v) =>
                                    _required(v, 'Please enter your first name'),
                                decoration: _decoration(
                                  hint: 'First name',
                                  icon: Icons.person_outline,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // LAST NAME
                              TextFormField(
                                controller: _lastNameController,
                                textInputAction: TextInputAction.next,
                                textCapitalization: TextCapitalization.words,
                                validator: (v) =>
                                    _required(v, 'Please enter your last name'),
                                decoration: _decoration(
                                  hint: 'Last name',
                                  icon: Icons.person_outline,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // COUNTRY (tap -> searchable list)
                              TextFormField(
                                controller: _countryController,
                                readOnly: true,
                                enableInteractiveSelection: false,
                                onTap: _pickCountry,
                                validator: (v) =>
                                    _required(v, 'Please select your country'),
                                decoration: _decoration(
                                  hint: 'Country',
                                  icon: Icons.public,
                                  suffix: _arrow,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // PHONE CODE (tap -> searchable list)
                              TextFormField(
                                controller: _phoneCodeController,
                                readOnly: true,
                                enableInteractiveSelection: false,
                                onTap: _pickPhoneCode,
                                validator: (v) =>
                                    _required(v, 'Please select the phone code'),
                                decoration: _decoration(
                                  hint: 'Phone code',
                                  icon: Icons.flag_outlined,
                                  suffix: _arrow,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // PHONE NUMBER
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(15),
                                ],
                                validator: _validatePhone,
                                decoration: _decoration(
                                  hint: 'Phone number',
                                  icon: Icons.phone_outlined,
                                ),
                              ),

                              const SizedBox(height: 12),

                              // TRUCK PLATE NUMBER (last field)
                              TextFormField(
                                controller: _plateController,
                                textInputAction: TextInputAction.done,
                                textCapitalization:
                                    TextCapitalization.characters,
                                validator: (v) => _required(
                                    v, 'Please enter your truck plate number'),
                                decoration: _decoration(
                                  hint: 'Truck plate number',
                                  icon: Icons.local_shipping_outlined,
                                ),
                              ),


                              const SizedBox(height: 20),

                              // BUTTONS: BACK + REGISTER
                              Row(
                                children: [
                                  // BACK
                                  Expanded(
                                    child: SizedBox(
                                      height: 50,
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
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
                                        child: const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.arrow_back_rounded,
                                              size: 20,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Back',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                                      child: ElevatedButton(
                                        onPressed: _register,
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
                            ],
                          ),
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
