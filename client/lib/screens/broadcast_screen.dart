import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _msgController = TextEditingController();
  bool _posting = false;
  Position? _pos;

  final List<Map<String, String>> _typeOptions = [
    {'label': 'Feeling unsafe', 'emoji': '😰'},
    {'label': 'Suspicious activity', 'emoji': '👀'},
    {'label': 'Need company', 'emoji': '🤝'},
    {'label': 'Other', 'emoji': '📢'},
  ];
  int _selectedType = 0;

  @override
  void initState() {
    super.initState();
    LocationService().getCurrentPosition().then((p) => setState(() => _pos = p));
  }

  Future<void> _post() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);

    await FirebaseFirestore.instance.collection('broadcasts').add({
      'message': text,
      'type': _typeOptions[_selectedType]['label'],
      'emoji': _typeOptions[_selectedType]['emoji'],
      'lat': _pos?.latitude ?? 0,
      'lng': _pos?.longitude ?? 0,
      'timestamp': FieldValue.serverTimestamp(),
      'user_id': FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
    });

    _msgController.clear();
    setState(() => _posting = false);
    if (mounted) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const Text('Community Feed',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
        ),
      ),
      body: Column(
        children: [
          // Post composer
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type selector
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _typeOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = _selectedType == i;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedType = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFF6C63FF) : const Color(0xFF0D0D1A),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? const Color(0xFF6C63FF) : Colors.white.withOpacity(0.1)),
                          ),
                          child: Text(
                            '${_typeOptions[i]['emoji']} ${_typeOptions[i]['label']}',
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF888899),
                              fontSize: 12,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Describe the situation briefly...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(width: 4),
                    Text(
                      _pos != null ? 'Posting from your location' : 'Location unavailable',
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _posting ? null : _post,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _posting
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Post', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Feed
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('broadcasts')
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('🌟', style: const TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      const Text('All clear nearby', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      const Text('No posts from your area yet', style: TextStyle(color: Color(0xFF666680), fontSize: 13)),
                    ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _buildPostCard(docs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final timestamp = d['timestamp'] as Timestamp?;
    final timeStr = timestamp != null ? _formatTime(timestamp.toDate()) : 'just now';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${d['emoji'] ?? '📢'} ${d['type'] ?? 'Post'}',
                style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const Spacer(),
            Text(timeStr, style: const TextStyle(color: Color(0xFF444460), fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          Text(d['message'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 12, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 3),
            Text('Nearby', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
          ]),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }
}