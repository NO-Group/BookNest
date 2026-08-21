import 'package:flutter/material.dart';

import '../../components/entity_groups_panel.dart';
import '../../../services/supabase_service.dart';
import '../../../config/theme.dart';

/// Organization detail screen (`/organization/:id`).
///
/// The full organization experience (announcements, roles, resources) is
/// still being built out; this version shows the organization's identity and
/// its Groups & Chat panel (default Chat group created automatically).
class OrganizationDetailScreen extends StatefulWidget {
  final String id;

  const OrganizationDetailScreen({super.key, required this.id});

  @override
  State<OrganizationDetailScreen> createState() => _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState extends State<OrganizationDetailScreen> {
  Map<String, dynamic>? _organization;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService().client
          .from('organizations')
          .select('*')
          .eq('id', widget.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _organization = row == null ? null : Map<String, dynamic>.from(row as Map);
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
        title:  Text('Organization', style: TextStyle(color: NOC.text, fontSize: 18)),
      ),
      body: _isLoading
          ?  Center(child: CircularProgressIndicator(color: NOC.accent))
          : _organization == null
              ?  Center(
                  child: Text(
                    'This organization could not be found.',
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
                          image: _organization!['cover_image_url'] != null
                              ? DecorationImage(
                                  image: NetworkImage(_organization!['cover_image_url'].toString()),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _organization!['cover_image_url'] == null
                            ?  Icon(Icons.business, color: NOC.accent, size: 32)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _organization!['name']?.toString() ?? 'Organization',
                        textAlign: TextAlign.center,
                        style:  TextStyle(
                          color: NOC.text,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if ((_organization!['description']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _organization!['description'].toString(),
                          textAlign: TextAlign.center,
                          style:  TextStyle(color: NOC.textMuted, fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    EntityGroupsPanel(
                      entityType: 'organization',
                      entityId: widget.id,
                    ),
                  ],
                ),
    );
  }
}
