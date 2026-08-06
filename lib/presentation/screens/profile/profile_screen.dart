import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final service = SupabaseService();
    final user = service.auth.currentUser;
    if (user == null) throw StateError('Please sign in to view your profile.');
    final profile = await service.client.from('profiles').select('username, display_name, avatar_url, bio').eq('id', user.id).maybeSingle();
    final statsResponse = await service.client.rpc('get_my_reading_stats');
    final stats = statsResponse is List && statsResponse.isNotEmpty ? statsResponse.first : statsResponse;
    return {
      'username': profile?['username'] ?? user.userMetadata?['username'] ?? 'Reader',
      'display_name': profile?['display_name'] ?? 'Reader',
      'avatar_url': profile?['avatar_url'],
      'bio': profile?['bio'] ?? '',
      ...Map<String, dynamic>.from(stats as Map? ?? const {}),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BookNestColors.darkBackground,
      appBar: AppBar(title: const Text('Profile')), 
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: BookNestColors.cyan));
          if (snapshot.hasError) return _ErrorState(message: 'Could not load your profile.', onRetry: () => setState(() => _profile = _loadProfile()));
          final data = snapshot.data!;
          final totalMinutes = _number(data['total_minutes']);
          final monthMinutes = _number(data['current_month_minutes']);
          return RefreshIndicator(
            color: BookNestColors.cyan,
            onRefresh: () async => setState(() => _profile = _loadProfile()),
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 110), children: [
              _profileHeader(data),
              const SizedBox(height: 24),
              const Text('Reading activity', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _StatCard(icon: Icons.schedule_outlined, value: _formatMinutes(totalMinutes), label: 'Total reading time', color: BookNestColors.cyan)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(icon: Icons.calendar_month_outlined, value: _formatMinutes(monthMinutes), label: 'This month', color: BookNestColors.yellow)),
              ]),
              const SizedBox(height: 12),
              _StatCard(icon: Icons.menu_book_outlined, value: '${_number(data['books_read'])}', label: 'Books read', color: BookNestColors.orange),
              const SizedBox(height: 18),
              const Text('Reading time is recorded by BookNest reading sessions. It is used to calculate BookWorm monthly gem allowances.', style: TextStyle(color: BookNestColors.darkTextSecondary, height: 1.45)),
            ]),
          );
        },
      ),
    );
  }

  Widget _profileHeader(Map<String, dynamic> data) {
    final avatar = data['avatar_url']?.toString();
    return Row(children: [
      CircleAvatar(radius: 34, backgroundColor: BookNestColors.cyan.withOpacity(.16), backgroundImage: avatar?.isNotEmpty == true ? NetworkImage(avatar!) : null, child: avatar?.isNotEmpty == true ? null : const Icon(Icons.person_outline, color: BookNestColors.cyan, size: 34)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(data['display_name'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)), Text('@${data['username']}', style: const TextStyle(color: BookNestColors.cyan)), if (data['bio'].toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text(data['bio'].toString(), style: const TextStyle(color: BookNestColors.darkTextSecondary)))])),
    ]);
  }

  int _number(dynamic value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  String _formatMinutes(int minutes) { final hours = minutes ~/ 60; final remaining = minutes % 60; if (hours == 0) return '${remaining}m'; return '${hours}h ${remaining}m'; }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String value; final String label; final Color color;
  const _StatCard({required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: BookNestColors.darkChatBackground, borderRadius: BorderRadius.circular(16), border: Border.all(color: BookNestColors.darkBorder)), child: Row(children: [Icon(icon, color: color, size: 26), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)), Text(label, style: const TextStyle(color: BookNestColors.darkTextSecondary, fontSize: 12))]))]));
}

class _ErrorState extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, style: const TextStyle(color: BookNestColors.darkTextSecondary)), const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('Retry'))]));
}
