import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/models.dart';
import '../services/sos_service.dart';

class SosDetailScreen extends StatefulWidget {
  final String sosId;
  const SosDetailScreen({super.key, required this.sosId});

  @override
  State<SosDetailScreen> createState() => _SosDetailScreenState();
}

class _SosDetailScreenState extends State<SosDetailScreen> {
  bool _accepted = false;
  bool _loading = false;
  SosEvent? _event;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    final doc = await FirebaseFirestore.instance
        .collection('sos_events')
        .doc(widget.sosId)
        .get();

    if (doc.exists && mounted) {
      setState(() => _event = SosEvent.fromDoc(doc));
    }
  }

  Future<void> _accept() async {
    setState(() => _loading = true);
    await SosService().acceptSos(widget.sosId);
    setState(() { _accepted = true; _loading = false; });

    // Launch navigation immediately
    if (_event != null) {
      await SosService().navigateTo(
        _event!.location.latitude,
        _event!.location.longitude,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        title: const Text(
          'SOS Alert',
          style: TextStyle(color: Color(0xFFFF4444), fontWeight: FontWeight.w700),
        ),
      ),
      body: _event == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4444)))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final e = _event!;
    final lat = e.location.latitude;
    final lng = e.location.longitude;

    return Column(
      children: [
        // Map showing victim location
        SizedBox(
          height: 280,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(lat, lng),
              zoom: 16,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('victim'),
                position: LatLng(lat, lng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: const InfoWindow(title: 'Person in distress'),
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
        ),

        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alert header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A0000),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF4444)),
                      ),
                      child: const Text(
                        'ACTIVE SOS',
                        style: TextStyle(
                          color: Color(0xFFFF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${e.responders.length} responding',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Info rows
                _infoRow(Icons.location_on_outlined, 'Location', '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'),
                const SizedBox(height: 12),
                _infoRow(Icons.access_time, 'Triggered', _formatTime(e.timestamp)),

                const Spacer(),

                // CTA
                if (!_accepted) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _accept,
                      icon: _loading
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.directions, color: Colors.white),
                      label: Text(
                        _loading ? 'Accepting...' : 'Accept & Navigate',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4444),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF112211),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF44FF88)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, color: Color(0xFF44FF88), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'You accepted — navigation opened',
                          style: TextStyle(color: Color(0xFF44FF88), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF666666), size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}