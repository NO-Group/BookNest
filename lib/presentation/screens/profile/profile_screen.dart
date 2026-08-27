import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/supabase_service.dart';

/// The reader's own profile. Per the architecture: the profile row lives in
/// Supabase (1:1 with the auth user, holds lightweight Cloudinary URLs),
/// while likes/follows/books come from MongoDB via the edge API.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploading = false;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;
  String get _email => SupabaseService().auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url, gems')
          .eq('id', _viewerId ?? '')
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profile = row == null ? null : Map<String, dynamic>.from(row);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayName {
    final name = (_profile?['display_name'] ?? _profile?['username'])
        ?.toString();
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final emailPrefix = _email.split('@').first;
    return emailPrefix.isEmpty ? 'BookNest reader' : emailPrefix;
  }

  String? get _avatarUrl {
    final url = _profile?['avatar_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  Future<void> _changeAvatar() async {
    // Imported lazily to keep the top clean and let the button work even if
    // the picker plugin fails on a given platform.
    final picked = await _pickImageBytes();
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    final url = await CloudinaryService.uploadImage(
      bytes: picked.$1,
      folder: 'avatars',
      publicId: 'avatar-${_viewerId ?? 'anon'}-${DateTime.now().millisecondsSinceEpoch}',
      extension: picked.$2,
    );
    if (!mounted) return;
    if (url == null) {
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Upload failed — check your connection and try again.')));
      return;
    }
    try {
      await SupabaseService()
          .client
          .from('profiles')
          .update({'avatar_url': url}).eq('id', _viewerId ?? '');
      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'avatar_url': url};
        _uploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New profile photo uploaded ✨')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Uploaded, but saving your profile failed.')));
    }
  }

  /// Returns (bytes, extension). Uses image_picker through a tiny indirection
  /// so the dependency stays isolated to this screen.
  Future<(Uint8List, String)?> _pickImageBytes() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'jpg';
      return (bytes, extension);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the photo picker on this device.')));
      }
      return null;
    }
  }

  Future<void> _editDisplayName() async {
    final controller =
        TextEditingController(text: _profile?['display_name']?.toString() ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Display name',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'What should readers call you?'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty || name.length > 60) return;
                  Navigator.pop(sheetContext);
                  try {
                    await SupabaseService()
                        .client
                        .from('profiles')
                        .update({'display_name': name}).eq(
                            'id', _viewerId ?? '');
                    if (!mounted) return;
                    setState(() =>
                        _profile = {...?_profile, 'display_name': name});
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Could not save your name.')));
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await SupabaseService().auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: BookNestColors.cyan)),
      );
    }

    return Scaffold(
      backgroundColor:
          dark ? BookNestColors.darkChatBackground : BookNestColors.lightSurface,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [BookNestColors.cyan, BookNestColors.navy],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: BookNestColors.navy,
                    backgroundImage:
                        _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                    child: _avatarUrl == null
                        ? Text(
                            _displayName.characters.isEmpty
                                ? '?'
                                : _displayName.characters.first.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w800),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: InkWell(
                    onTap: _uploading ? null : _changeAvatar,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BookNestColors.cyan,
                        border: Border.all(
                            color: dark
                                ? BookNestColors.darkChatBackground
                                : Colors.white,
                            width: 2.5),
                      ),
                      child: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.photo_camera_rounded,
                              size: 18, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _editDisplayName,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_rounded,
                        size: 17, color: BookNestColors.cyan),
                  ],
                ),
              ),
            ),
            if (_profile?['username']?.toString().isNotEmpty == true)
              Text('@${_profile?['username']}',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_email, style: TextStyle(color: theme.hintColor, fontSize: 13)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: BookNestColors.cyan.withOpacity(.1),
                border: Border.all(color: BookNestColors.cyan.withOpacity(.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond_rounded,
                      color: BookNestColors.cyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_profile?['gems'] ?? 0} gems',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            _ProfileAction(
              icon: Icons.forum_rounded,
              label: 'Messages',
              subtitle: 'Your conversations',
              onTap: () => context.go('/dms'),
            ),
            _ProfileAction(
              icon: Icons.menu_book_rounded,
              label: 'My library',
              subtitle: 'Books you love and write',
              onTap: () => context.push('/books'),
            ),
            _ProfileAction(
              icon: Icons.logout_rounded,
              label: 'Sign out',
              subtitle: _email,
              danger: true,
              onTap: _signOut,
            ),
            const SizedBox(height: 18),
            Text(
              'BookNest v1.1 · by N.O Group',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : BookNestColors.cyan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withOpacity(.12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            title: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.hintColor, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
        ),
      ),
    );
  }
}
