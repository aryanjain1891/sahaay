import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pinput/pinput.dart';
import '../main.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();

  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _verificationId;

  // ─── Step 1: Send OTP ─────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = '+91${_phoneController.text.trim()}';
    if (phone.length != 13) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }

    setState(() { _loading = true; _error = null; });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Auto-retrieval on Android
        await _signInWithCredential(credential);
      },
      verificationFailed: (e) {
        setState(() {
          _error = e.message ?? 'Verification failed';
          _loading = false;
        });
      },
      codeSent: (verificationId, _) {
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _loading = false;
        });
        _pinFocus.requestFocus();
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ─── Step 2: Verify OTP ───────────────────────────────────────────────────

  Future<void> _verifyOtp(String otp) async {
    if (_verificationId == null) return;
    setState(() { _loading = true; _error = null; });

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      // Navigator handled by StreamBuilder in main.dart
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Invalid OTP';
        _loading = false;
      });
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / wordmark
              const Text(
                'sahaay',
                style: TextStyle(
                  color: Color(0xFFFF4444),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent ? 'Enter the OTP sent to your number' : 'Your safety network, nearby.',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 15),
              ),

              const Spacer(),

              if (!_codeSent) ...[
                // Phone input
                const Text(
                  'Phone number',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF333333)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('+91', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        focusNode: _phoneFocus,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '98765 43210',
                          hintStyle: const TextStyle(color: Color(0xFF444444)),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF333333)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF333333)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFFF4444)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // OTP input
                const Text(
                  'One-time password',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Pinput(
                  controller: _pinController,
                  focusNode: _pinFocus,
                  length: 6,
                  autofocus: true,
                  defaultTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF333333)),
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  focusedPinTheme: PinTheme(
                    width: 48,
                    height: 56,
                    textStyle: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFFF4444), width: 2),
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  onCompleted: _verifyOtp,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() { _codeSent = false; _pinController.clear(); }),
                  child: const Text(
                    'Wrong number? Go back',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF4444), fontSize: 13)),
              ],

              const SizedBox(height: 24),

              // CTA button
              if (!_codeSent)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4444),
                      disabledBackgroundColor: const Color(0xFF441111),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Send OTP',
                            style: TextStyle(
                              color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _phoneFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }
}
