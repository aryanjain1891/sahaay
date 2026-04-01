import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class ReportIncidentScreen extends StatefulWidget {
  final LatLng initialPosition;
  const ReportIncidentScreen({super.key, required this.initialPosition});
  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  late LatLng _pinPosition;
  bool _submitting = false;
  int _selectedIncident = 0;
  final _descController = TextEditingController();

  final List<Map<String, dynamic>> _incidentTypes = [
    {'label': 'Theft / Robbery', 'emoji': '💰', 'color': 0xFFFF4444},
    {'label': 'Harassment', 'emoji': '⚠️', 'color': 0xFFFF8C00},
    {'label': 'Suspicious person', 'emoji': '👤', 'color': 0xFFFFD700},
    {'label': 'Poor lighting', 'emoji': '🔦', 'color': 0xFF6C63FF},
    {'label': 'Unsafe road', 'emoji': '🚧', 'color': 0xFF00BCD4},
    {'label': 'Other', 'emoji': '📍', 'color': 0xFF888899},
  ];

  @override
  void initState() {
    super.initState();
    _pinPosition = widget.initialPosition;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    await FirebaseFirestore.instance.collection('incidents').add({
      'type': _incidentTypes[_selectedIncident]['label'],
      'emoji': _incidentTypes[_selectedIncident]['emoji'],
      'description': _descController.text.trim(),
      'lat': _pinPosition.latitude,
      'lng': _pinPosition.longitude,
      'timestamp': FieldValue.serverTimestamp(),
      'intensity': _incidentTypes[_selectedIncident]['label'] == 'Theft / Robbery' ? 0.9
          : _incidentTypes[_selectedIncident]['label'] == 'Harassment' ? 0.7
          : 0.4,
    });

    setState(() => _submitting = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Incident reported — thank you'),
        backgroundColor: Color(0xFF1A2E1A),
      ));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text('Report Incident',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Map with draggable pin
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  onMapCreated: (ctrl) => _mapController.complete(ctrl),
                  initialCameraPosition: CameraPosition(target: _pinPosition, zoom: 15),
                  onCameraMove: (pos) => setState(() => _pinPosition = pos.target),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  style: _darkStyle,
                ),
                // Center pin
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_pin, color: Color(0xFFFF4444), size: 40),
                    SizedBox(height: 20),
                  ],
                ),
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Drag map to pin location',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Incident type',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 2.2),
                    itemCount: _incidentTypes.length,
                    itemBuilder: (_, i) {
                      final selected = _selectedIncident == i;
                      final color = Color(_incidentTypes[i]['color']);
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIncident = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: selected ? color.withOpacity(0.2) : const Color(0xFF1A1A2E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? color : Colors.white.withOpacity(0.08)),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(_incidentTypes[i]['emoji'], style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(_incidentTypes[i]['label'],
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? color : const Color(0xFF888899),
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              )),
                          ]),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                  const Text('Description (optional)',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Briefly describe what happened...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1A1A2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF6C63FF)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4444),
                        disabledBackgroundColor: const Color(0xFF441111),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Submit Report',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const String _darkStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#16213e"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f2027"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#16213e"}]}
  ]''';

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }
}