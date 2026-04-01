import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/sos_service.dart';
import '../services/location_service.dart';
import 'broadcast_screen.dart';
import 'report_incident_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController = Completer();

  bool _sosActive = false;
  bool _inCancelWindow = false;
  String? _activeSosId;
  double _holdProgress = 0.0;
  Timer? _holdTimer;
  Timer? _cancelTimer;

  Position? _currentPosition;
  Set<Circle> _circles = {};
  int _selectedTab = 0;

  late AnimationController _pulseController;
  late AnimationController _sosScaleController;
  late Animation<double> _sosScaleAnim;

  final List<Map<String, dynamic>> _crimeZones = [
    {'lat': 28.6139, 'lng': 77.2090, 'radius': 300.0, 'intensity': 0.9, 'label': 'High incidents'},
    {'lat': 28.6200, 'lng': 77.2150, 'radius': 200.0, 'intensity': 0.5, 'label': 'Moderate incidents'},
    {'lat': 28.6080, 'lng': 77.2020, 'radius': 250.0, 'intensity': 0.2, 'label': 'Low incidents'},
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _sosScaleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _sosScaleAnim = Tween(begin: 1.0, end: 0.92).animate(CurvedAnimation(parent: _sosScaleController, curve: Curves.easeInOut));
    _initLocation();
    _buildCrimeCircles();
  }

  Future<void> _initLocation() async {
    final pos = await LocationService().getCurrentPosition();
    if (pos != null && mounted) {
      setState(() => _currentPosition = pos);
      final ctrl = await _mapController.future;
      ctrl.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
    }
    LocationService().startPeriodicUpdates();
  }

  void _buildCrimeCircles() {
    final circles = <Circle>{};
    for (int i = 0; i < _crimeZones.length; i++) {
      final z = _crimeZones[i];
      final intensity = z['intensity'] as double;
      circles.add(Circle(
        circleId: CircleId('crime_$i'),
        center: LatLng(z['lat'], z['lng']),
        radius: z['radius'],
        fillColor: _crimeColor(intensity).withOpacity(0.25),
        strokeColor: _crimeColor(intensity).withOpacity(0.6),
        strokeWidth: 2,
      ));
    }
    setState(() => _circles = circles);
  }

  Color _crimeColor(double intensity) {
    if (intensity > 0.7) return const Color(0xFFFF2D2D);
    if (intensity > 0.4) return const Color(0xFFFF8C00);
    return const Color(0xFFFFD700);
  }

  void _onHoldStart() {
    HapticFeedback.mediumImpact();
    _sosScaleController.forward();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 20), (t) {
      setState(() => _holdProgress = (t.tick * 20) / 2000);
      if (_holdProgress >= 1.0) { t.cancel(); _fireSos(); }
    });
  }

  void _onHoldEnd() {
    _holdTimer?.cancel();
    _sosScaleController.reverse();
    setState(() => _holdProgress = 0.0);
  }

  Future<void> _fireSos() async {
    HapticFeedback.heavyImpact();
    _sosScaleController.reverse();
    final result = await SosService().triggerSos();
    if (!mounted) return;
    if (result.ok) {
      setState(() { _sosActive = true; _inCancelWindow = true; _activeSosId = result.sosId; _holdProgress = 0.0; });
      _cancelTimer = Timer(const Duration(seconds: 5), () { if (mounted) setState(() => _inCancelWindow = false); });
    } else if (result.wasDebounced) {
      _showSnack('Please wait before triggering again');
    } else {
      _showSnack('Could not send SOS — check connection');
    }
  }

  Future<void> _cancelSos() async {
    _cancelTimer?.cancel();
    if (_activeSosId != null) await SosService().cancelSos(_activeSosId!);
    setState(() { _sosActive = false; _inCancelWindow = false; _activeSosId = null; });
    _showSnack('SOS cancelled');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: const Color(0xFF1E1E2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomPanel()),
          if (_inCancelWindow)
            Positioned(left: 16, right: 16, bottom: 290, child: _buildCancelBanner()),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return GoogleMap(
      onMapCreated: (ctrl) => _mapController.complete(ctrl),
      initialCameraPosition: CameraPosition(
        target: _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const LatLng(28.6139, 77.2090),
        zoom: 15,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      circles: _circles,
      style: _mapStyle,
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16, bottom: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.75), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            const Text('sahaay', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFFF4444), borderRadius: BorderRadius.circular(20)),
              child: const Text('BETA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _showLegend,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.circle, color: Color(0xFFFFD700), size: 8),
                  SizedBox(width: 3),
                  Icon(Icons.circle, color: Color(0xFFFF8C00), size: 8),
                  SizedBox(width: 3),
                  Icon(Icons.circle, color: Color(0xFFFF2D2D), size: 8),
                  SizedBox(width: 6),
                  Text('Zones', style: TextStyle(color: Colors.white, fontSize: 11)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _tabChip('Map', 0, Icons.map_outlined),
              const SizedBox(width: 8),
              _tabChip('Feed', 1, Icons.feed_outlined),
              const SizedBox(width: 8),
              _tabChip('Report', 2, Icons.flag_outlined),
              const Spacer(),
              Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF44FF88), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Available', style: TextStyle(color: Color(0xFF666680), fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          _buildSosButton(),
          const SizedBox(height: 12),
          Text(
            _sosActive ? 'SOS ACTIVE — Help is on the way' : 'Hold for 2 seconds to send SOS',
            style: TextStyle(
              color: _sosActive ? const Color(0xFFFF4444) : const Color(0xFF666680),
              fontSize: 13, fontWeight: _sosActive ? FontWeight.w600 : FontWeight.w400),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _tabChip(String label, int index, IconData icon) {
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTab = index);
        if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const BroadcastScreen()));
        if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => ReportIncidentScreen(
          initialPosition: _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : const LatLng(28.6139, 77.2090),
        )));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF4444) : const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFFFF4444) : Colors.white.withOpacity(0.1)),
        ),
        child: Row(children: [
          Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF666680)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: selected ? Colors.white : const Color(0xFF666680), fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _buildSosButton() {
    return GestureDetector(
      onLongPressStart: (_) => _onHoldStart(),
      onLongPressEnd: (_) => _onHoldEnd(),
      onLongPressCancel: _onHoldEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _sosScaleAnim]),
        builder: (_, __) => Transform.scale(
          scale: _sosScaleAnim.value,
          child: Stack(alignment: Alignment.center, children: [
            if (_sosActive)
              Container(
                width: 140 + (_pulseController.value * 20),
                height: 140 + (_pulseController.value * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFF4444).withOpacity(0.4 - (_pulseController.value * 0.3)),
                    width: 2,
                  ),
                ),
              ),
            SizedBox(
              width: 130, height: 130,
              child: CircularProgressIndicator(
                value: _holdProgress > 0 ? _holdProgress : (_sosActive ? 1.0 : 0.0),
                strokeWidth: 3,
                backgroundColor: Colors.white.withOpacity(0.05),
                color: const Color(0xFFFF4444),
              ),
            ),
            Container(
              width: 114, height: 114,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: _sosActive
                    ? [const Color(0xFFFF6B6B), const Color(0xFFCC0000)]
                    : [const Color(0xFF2A0A0A), const Color(0xFF1A0505)]),
                border: Border.all(color: const Color(0xFFFF4444), width: _sosActive ? 2.5 : 1.5),
                boxShadow: _sosActive ? [BoxShadow(color: const Color(0xFFFF4444).withOpacity(0.5), blurRadius: 24, spreadRadius: 4)] : [],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_sosActive ? Icons.warning_rounded : Icons.sos_rounded, size: 36, color: Colors.white),
                const SizedBox(height: 2),
                Text(_sosActive ? 'ACTIVE' : 'SOS',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCancelBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.5)),
        boxShadow: [BoxShadow(color: const Color(0xFFFF4444).withOpacity(0.2), blurRadius: 16)],
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF4444), size: 20),
        const SizedBox(width: 10),
        const Expanded(child: Text('Accidental trigger?', style: TextStyle(color: Colors.white, fontSize: 14))),
        GestureDetector(
          onTap: _cancelSos,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFF4444), borderRadius: BorderRadius.circular(10)),
            child: const Text('Cancel', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  void _showLegend() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0D1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Safety zone legend', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _legendRow(const Color(0xFFFFD700), 'Low incidents', '1–3 reports'),
          _legendRow(const Color(0xFFFF8C00), 'Moderate incidents', '4–10 reports'),
          _legendRow(const Color(0xFFFF2D2D), 'High incidents', '10+ reports'),
          const SizedBox(height: 8),
          const Text('Tap "Report" to add an incident in your area.', style: TextStyle(color: Color(0xFF666680), fontSize: 13)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _legendRow(Color color, String label, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
          Text(sub, style: const TextStyle(color: Color(0xFF666680), fontSize: 12)),
        ]),
      ]),
    );
  }

  static const String _mapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#16213e"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f2027"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#16213e"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]}
  ]''';

  @override
  void dispose() {
    _holdTimer?.cancel();
    _cancelTimer?.cancel();
    _pulseController.dispose();
    _sosScaleController.dispose();
    LocationService().stopPeriodicUpdates();
    super.dispose();
  }
}