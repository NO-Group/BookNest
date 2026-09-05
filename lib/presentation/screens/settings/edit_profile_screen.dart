import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../services/avatar_uploader.dart';
import '../../../services/supabase_service.dart';
import '../../components/booknest_ui.dart';

/// Full profile editor: avatar (Cloudinary), display name, username, phone.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;

  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _phone;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController();
    _username = TextEditingController();
    _phone = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('id, username, display_name, avatar_url, phone_number')
          .eq('id', _viewerId ?? '')
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _profile = row == null ? null : Map<String, dynamic>.from(row);
        _displayName.text =
            _profile?['display_name']?.toString() ?? '';
        _username.text = _profile?['username']?.toString() ?? '';
        _phone.text = _profile?['phone_number']?.toString() ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _avatarUrl {
    final url = _profile?['avatar_url']?.toString();
    return url != null && url.startsWith('http') ? url : '';
  }

  Future<void> _changeAvatar() async {
    setState(() => _uploadingAvatar = true);
    final url = await AvatarUploader.pickAndUpload(userId: _viewerId ?? 'anon');
    if (!mounted) return;
    if (url == null) {
      setState(() => _uploadingAvatar = false);
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
        _uploadingAvatar = false;
      });
    } catch (_) {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    final displayName = _displayName.text.trim();
    if (displayName.isEmpty || displayName.length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Display name must be 1–60 characters.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseService().client.from('profiles').update({
        'display_name': displayName,
        'phone_number': _phone.text.trim(),
      }).eq('id', _viewerId ?? '');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved ✓')));
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save — check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: BookNestColors.cyan)));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Edit profile',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Stack(
              children: [
                BookNestAvatar(
                  imageUrl: _avatarUrl.isEmpty ? null : _avatarUrl,
                  name: _displayName.text.isEmpty
                      ? 'Reader'
                      : _displayName.text,
                  radius: 46,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: InkWell(
                    onTap: _uploadingAvatar ? null : _changeAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: BookNestColors.cyan,
                        border: Border.all(
                            color: theme.scaffoldBackgroundColor, width: 2.5),
                      ),
                      child: _uploadingAvatar
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: BookNestColors.navyDeep))
                          : const Icon(Icons.photo_camera_rounded,
                              size: 17, color: BookNestColors.navyDeep),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _LabeledField(
                label: 'Display name',
                controller: _displayName,
                hint: 'What readers call you'),
            const SizedBox(height: 16),
            _LabeledField(
              label: 'Username',
              controller: _username,
              hint: _profile?['username']?.toString().isEmpty == true
                  ? 'Not set yet'
                  : 'Username',
              enabled: false,
            ),
            const SizedBox(height: 16),
            _LabeledField(
                label: 'Phone number',
                controller: _phone,
                hint: 'For account recovery',
                keyboardType: TextInputType.phone),
            const SizedBox(height: 30),
            GradientButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _save),
            const SizedBox(height: 12),
            Text('Username changes are coming with the community update.',
                style: TextStyle(
                    color: theme.hintColor,
                    fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final TextInputType? keyboardType;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: BookNestColors.cyan, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
