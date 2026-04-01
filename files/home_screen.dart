import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../sos_service.dart';
import '../services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _isAvailable = true;
  bool _sosActive = false;
  bool _inCancelWindow = false;
  String? _activeSosId;

  Timer? _cancelWindowTimer;
  Timer? _holdTimer;

  late AnimationController _pulseController;
  late AnimationController _holdController;

  // Hold progress (0.0 → 1.0 over 2 seconds)
  double _holdProgress = 0.0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    LocationService().startPeriodicUpdates();
  }

  // ─── Hold gesture logic ───────────────────────────────────────────────────

  void _onHoldStart() {
    HapticFeedback.mediumImpact();
    _holdController.forward(from: 0);

    _holdTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      setState(() => _holdProgress = t.tick / (2000 / 16));
      if (_holdProgress >= 1.0) {
        t.cancel();
        _fireSos();
      }
    });
  }

  void _onHoldEnd() {
    _holdTimer?.cancel();
    _holdController.reverse();
    setState(() => _holdProgress = 0.0);
  }

  Future<void> _fireSos() async {
    HapticFeedback.heavyImpact();

    final result = await SosService().triggerSos();

    if (result.ok) {
      setState(() {
        _sosActive = true;
        _inCancelWindow = true;
        _activeSosId = result.sosId;
        _holdProgress = 0.0;
      });

      // 5-second cancel window
      _cancelWindowTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _inCancelWindow = false);
      });
    } else if (result.wasDebounced) {
      _showSnack('Please wait before triggering again');
    } else {
      _showSnack(result.errorMessage ?? 'Something went wrong');
    }
  }

  Future<void> _cancelSos() async {
    _cancelWindowTimer?.cancel();
    if (_activeSosId != null) {
      await SosService().cancelSos(_activeSosId!);
    }
    setState(() {
      _sosActive = false;
      _inCancelWindow = false;
      _activeSosId = null;
    });
    _showSnack('SOS cancelled');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF222222)),
    );
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const Spacer(),
            _buildSosButton(),
            const SizedBox(height: 24),
            _buildButtonLabel(),
            if (_inCancelWindow) _buildCancelBanner(),
            const Spacer(),
            _buildAvailabilityToggle(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'sahaay',
            style: TextStyle(
              color: Color(0xFFFF4444),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: _isAvailable ? const Color(0xFF44FF88) : const Color(0xFF444444),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isAvailable ? 'Available' : 'Unavailable',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    return GestureDetector(
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressCancel: _onHoldEnd,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) {
          final pulseScale = _sosActive
              ? 1.0 + (_pulseController.value * 0.08)
              : 1.0;

          return Transform.scale(
            scale: pulseScale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer pulse ring (only when SOS active)
                if (_sosActive)
                  Container(
                    width: 220 + (_pulseController.value * 30),
                    height: 220 + (_pulseController.value * 30),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF4444)
                            .withOpacity(0.3 - (_pulseController.value * 0.2)),
                        width: 2,
                      ),
                    ),
                  ),

                // Progress ring while holding
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: _holdProgress,
                    strokeWidth: 4,
                    backgroundColor: const Color(0xFF222222),
                    color: const Color(0xFFFF4444),
                  ),
                ),

                // Main button
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _sosActive
                        ? const Color(0xFFFF4444)
                        : const Color(0xFF1A1A1A),
                    border: Border.all(
                      color: const Color(0xFFFF4444),
                      width: _sosActive ? 0 : 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _sosActive ? Icons.warning_rounded : Icons.sos_rounded,
                        size: 56,
                        color: _sosActive ? Colors.white : const Color(0xFFFF4444),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _sosActive ? 'ACTIVE' : 'SOS',
                        style: TextStyle(
                          color: _sosActive ? Colors.white : const Color(0xFFFF4444),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildButtonLabel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Text(
        _sosActive
            ? 'Help is on the way. Responders have been notified.'
            : 'Hold for 2 seconds to send SOS',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF666666), fontSize: 14),
      ),
    );
  }

  Widget _buildCancelBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF441111)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Accidental trigger?',
            style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
          ),
          GestureDetector(
            onTap: _cancelSos,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF331111),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF4444)),
              ),
              child: const Text(
                'Cancel SOS',
                style: TextStyle(
                  color: Color(0xFFFF4444),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Available to help others',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                _isAvailable ? 'You can receive SOS alerts nearby' : 'You won\'t receive alerts',
                style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
              ),
            ],
          ),
          Switch(
            value: _isAvailable,
            onChanged: (v) {
              setState(() => _isAvailable = v);
              // TODO: persist to Firestore via UserService
            },
            activeColor: const Color(0xFF44FF88),
            activeTrackColor: const Color(0xFF112211),
            inactiveThumbColor: const Color(0xFF444444),
            inactiveTrackColor: const Color(0xFF1A1A1A),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cancelWindowTimer?.cancel();
    _holdTimer?.cancel();
    _pulseController.dispose();
    _holdController.dispose();
    LocationService().stopPeriodicUpdates();
    super.dispose();
  }
}
