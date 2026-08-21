import 'package:flutter/material.dart';

import '../../components/entity_groups_panel.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

/// Club detail screen (`/club/:id`).
///
/// The full club experience (threads, members, library) is still being built
/// out; this version loads the club's identity and shows its Groups & Chat
/// panel (default Chat group created automatically on club creation).
class ClubDetailScreen extends StatefulWidget {
  final String clubId;

  const ClubDetailScreen({super.key, required this.clubId});

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen> {
  Map<String, dynamic>? _club;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService().client
          .from('clubs')
          .select('*')
          .eq('id', widget.clubId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _club = row == null ? null : Map<String, dynamic>.from(row as Map);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(
        backgroundColor: NOC.surface,
        elevation: 1,
        title:  Text('Club', style: TextStyle(color: NOC.text, fontSize: 18)),
      ),
      body: _isLoading
          ?  Center(child: CircularProgressIndicator(color: NOC.accent))
          : _club == null
              ?  Center(
                  child: Text(
                    'This club could not be found.',
                    style: TextStyle(color: NOC.textMuted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 40),
                  children: [
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: NOC.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          image: _club!['cover_image_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(_club!['cover_image_url'].toString()),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _club!['cover_image_url'] == null
                            ?  Icon(Icons.menu_book, color: NOC.hot, size: 32)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _club!['name']?.toString() ?? 'Club',
                        textAlign: TextAlign.center,
                        style:  TextStyle(
                          color: NOC.text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if ((_club!['description']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _club!['description'].toString(),
                          textAlign: TextAlign.center,
                          style:  TextStyle(color: NOC.textMuted, fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    EntityGroupsPanel(
                      entityType: 'club',
                      entityId: widget.clubId,
                    ),
                  ],
                ),
    );
  }
}
