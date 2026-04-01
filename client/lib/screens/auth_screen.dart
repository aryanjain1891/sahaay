import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pinput/pinput.dart';

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

  // ─── Send OTP ────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = '+91${_phoneController.text.trim()}';
    if (_phoneController.text.trim().length != 10) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
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

  // ─── Verify OTP ──────────────────────────────────────────────────────────

  Future<void> _verifyOtp(String otp) async {
    if (_verificationId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Invalid OTP';
        _loading = false;
      });
    }
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
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
    );

    final focusedTheme = pinTheme.copyDecorationWith(
      border: Border.all(color: const Color(0xFFFF4444), width: 2),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'sahaay',
                style: TextStyle(
                  color: Color(0xFFFF4444),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _codeSent
                    ? 'Enter the OTP sent to your number'
                    : 'Your safety network, nearby.',
                style: const TextStyle(color: Color(0xFF888888)),
              ),

              const Spacer(),

              if (!_codeSent) ...[
                const Text('Phone number',
                    style: TextStyle(color: Color(0xFFCCCCCC))),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '9876543210',
                    filled: true,
                    fillColor: Color(0xFF1A1A1A),
                  ),
                ),
              ] else ...[
                const Text('One-time password',
                    style: TextStyle(color: Color(0xFFCCCCCC))),
                const SizedBox(height: 16),

                // ✅ FIXED HERE
                Pinput(
                  controller: _pinController,
                  focusNode: _pinFocus,
                  length: 6,
                  autofocus: true,
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: focusedTheme,
                  onCompleted: _verifyOtp,
                ),
              ],

              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),

              const SizedBox(height: 24),

              if (!_codeSent)
                ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Send OTP'),
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