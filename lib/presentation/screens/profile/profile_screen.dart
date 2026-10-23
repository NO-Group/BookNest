import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme.dart';
import '../../../config/app_config.dart';
import '../../../services/backend_api.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/push_service.dart';
import '../../../services/supabase_service.dart';
import '../../../services/profile_layout.dart';
import '../../../services/reader_profile.dart';
import '../../../config/locales.dart';
import '../../components/booknest_keyboard.dart';
import '../chat/media_viewer_screen.dart';
import '../../components/adaptive.dart';

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
  bool _coverUploading = false;

  String? get _viewerId => SupabaseService().auth.currentUser?.id;
  String get _email => SupabaseService().auth.currentUser?.email ?? '';
  String _mode = 'reader'; // 'reader' | 'author'
  bool _modeBusy = false;
  /// The overall moderator's account. Display gate only — every real
  /// power is enforced by the edge function against the signed-in email.
  bool get _isOverallModerator =>
      _email.toLowerCase() == 'n.ogroup@yahoo.com';
  String? _cloudStatus; // null = checking, 'online' | 'offline'

  @override
  void initState() {
    super.initState();
    ReaderProfile.ensureLoaded();
    _load();
    _probeCloud();
    _loadMode();
  }

  Future<void> _loadMode() async {
    final res = await BackendApi.instance.call('profile.mode.get');
    final mode = res?['mode']?.toString();
    final next = mode == 'author' ? 'author' : 'reader';
    if (mounted) setState(() => _mode = next);
  }

  Future<void> _switchMode() async {
    if (_modeBusy) return;
    final next = _mode == 'author' ? 'reader' : 'author';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(next == 'author'
            ? 'Switch to Author mode?'
            : 'Switch to Reader mode?'),
        content: Text(next == 'author'
            ? 'Your profile gains the Author mark and your writing tools '
                'come to the front — studio, dashboard and analytics. Your '
                'reads, saves and streaks stay exactly as they are.'
            : 'Your profile returns to the reader view — your books stay '
                'published and nothing is lost. You can switch back any '
                'time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Switch',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _modeBusy = true);
    final res = await BackendApi.instance
        .call('profile.mode.set', {'mode': next});
    if (!mounted) return;
    setState(() {
      _modeBusy = false;
      if (res != null) _mode = next;
    });
  }

  /// Terminal-free deployment check: pings the booknest-api edge function.
  Future<void> _probeCloud() async {
    final online = await BackendApi.instance.probe();
    if (!mounted) return;
    setState(() => _cloudStatus = online ? 'online' : 'offline');
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
      _loadCover();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Read on its own so the profile still loads if the column is missing.
  Future<void> _loadCover() async {
    try {
      final row = await SupabaseService()
          .client
          .from('profiles')
          .select('cover_url')
          .eq('id', _viewerId ?? '')
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _profile = {...?_profile, 'cover_url': row['cover_url']});
    } catch (_) {}
  }

  String? get _coverUrl {
    final url = _profile?['cover_url']?.toString();
    return url != null && url.startsWith('http') ? url : null;
  }

  Future<void> _saveCover(String? url) async {
    try {
      await SupabaseService().updateRow('profiles', {'cover_url': url},
          column: 'id', equals: _viewerId ?? '');
      final saved = await SupabaseService()
          .client
          .from('profiles')
          .select('cover_url')
          .eq('id', _viewerId ?? '')
          .maybeSingle();
      final persisted = saved != null && saved['cover_url']?.toString() == url;
      if (!mounted) return;
      setState(() {
        if (persisted) _profile = {...?_profile, 'cover_url': url};
        _coverUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!persisted
              ? 'The cover could not be saved — please try again.'
              : url == null
                  ? 'Cover photo removed.'
                  : 'New cover photo saved ✨')));
    } on WriteException catch (e) {
      if (!mounted) return;
      setState(() => _coverUploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _coverUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The cover could not be saved — please try again.')));
    }
  }

  Future<void> _changeCover() async {
    final picked = await _pickImageBytes(maxWidth: 1920, maxHeight: 1080);
    if (picked == null || !mounted) return;
    setState(() => _coverUploading = true);
    final url = await CloudinaryService.uploadImage(
      bytes: picked.$1,
      folder: 'profile_covers',
      publicId:
          'cover-${_viewerId ?? 'anon'}-${DateTime.now().millisecondsSinceEpoch}',
      extension: picked.$2,
    );
    if (!mounted) return;
    if (url == null) {
      setState(() => _coverUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Upload failed — check your connection and try again.')));
      return;
    }
    await _saveCover(url);
  }

  Future<void> _coverMenu() async {
    if (_coverUploading) return;
    if (_coverUrl == null) return _changeCover();
    final choice = await showModalBottomSheet<String>(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      showDragHandle: true,
      builder: (sheet) => SheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: BookNestColors.cyan),
              title: const Text('Change cover photo'),
              onTap: () => Navigator.pop(sheet, 'change'),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_out_map_rounded,
                  color: BookNestColors.cyan),
              title: const Text('View cover photo'),
              onTap: () => Navigator.pop(sheet, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFD06A6A)),
              title: const Text('Remove cover photo'),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'change') return _changeCover();
    if (choice == 'view') {
      return openChatPhoto(context, _coverUrl!,
          album: [MediaItem(url: _coverUrl!, name: 'Cover photo')]);
    }
    setState(() => _coverUploading = true);
    await _saveCover(null);
  }

  /// The cover band across the top of the profile: the reader's cover
  /// photo, or the BookNest gradient until they add one.
  Widget _coverBand(bool studio, {double height = _coverHeight}) {
    final url = _coverUrl;
    return GestureDetector(
      onTap: url == null
          ? _coverMenu
          : () => openChatPhoto(context, url,
              album: [MediaItem(url: url, name: 'Cover photo')]),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: studio
                        ? [
                            BookNestColors.navy,
                            BookNestColors.navyDeep,
                            BookNestColors.cyan.withOpacity(.55),
                          ]
                        : [
                            BookNestColors.navyDeep,
                            BookNestColors.navy,
                            BookNestColors.cyan.withOpacity(.35),
                          ],
                  ),
                ),
              ),
              if (url == null)
                Positioned(
                  right: 34,
                  top: 40,
                  child: Icon(Icons.auto_stories_rounded,
                      size: 64, color: Colors.white.withOpacity(.10)),
                ),
              if (url != null)
                CachedNetworkImage(
                  imageUrl: CloudinaryService.transformUrl(url, width: 1280),
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              // Keeps the avatar ring and buttons readable on any photo.
              if (url != null)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x33000000), Color(0x00000000), Color(0x55000000)],
                      stops: [0, .45, 1],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _coverHeight = 176;

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
      await SupabaseService().updateRow('profiles', {'avatar_url': url},
          column: 'id', equals: _viewerId ?? '');
      // Verify the write actually persisted before celebrating — the
      // cloud chip only means the API is reachable, so we double-check.
      final saved = await SupabaseService()
          .client
          .from('profiles')
          .select('avatar_url')
          .eq('id', _viewerId ?? '')
          .maybeSingle();
      final persisted =
          saved != null && saved['avatar_url']?.toString() == url;
      if (!mounted) return;
      setState(() {
        if (persisted) _profile = {...?_profile, 'avatar_url': url};
        _uploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(persisted
              ? 'New profile photo saved ✨'
              : 'Uploaded — but the save could not be verified. Reopen your profile and retry.')));
    } on WriteException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Uploaded, but saving your profile failed.')));
    }
  }

  /// Returns (bytes, extension). Uses image_picker through a tiny indirection
  /// so the dependency stays isolated to this screen.
  Future<(Uint8List, String)?> _pickImageBytes(
      {double maxWidth = 1024, double maxHeight = 1024}) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
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
    // This phone stops receiving the account's pushes (needs the session).
    await PushService.instance.tearDown();
    await SupabaseService().auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: BookNestColors.cyan)),
      );
    }

    return ValueListenableBuilder<String>(
      valueListenable: profileLayout,
      builder: (context, layout, __) {
        final studio = layout == 'studio';
        return Scaffold(
          backgroundColor: dark
              ? BookNestColors.darkChatBackground
              : BookNestColors.lightSurface,
          body: LayoutBuilder(builder: (context, box) {
            return box.maxWidth >= 1000
                ? _wideLayout(context, studio, dark, box.maxWidth)
                : _phoneLayout(context, studio, dark, box.maxWidth);
          }),
        );
      },
    );
  }

  // ── Phone / tablet portrait: one column, cover bleeding to the edges ─
  Widget _phoneLayout(
      BuildContext context, bool studio, bool dark, double width) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bandH = topPad + (width * .36).clamp(128.0, 200.0);
    const avatarR = 50.0;
    // Tablets in portrait keep the column readable.
    final side = width > 720 ? (width - 680) / 2 : 18.0;
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: context.isCompact ? 120 : 40),
      child: Column(
        children: [
          SizedBox(
            height: bandH + avatarR + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: bandH,
                    child: _coverBand(studio, height: bandH)),
                Positioned(
                  top: topPad + 10,
                  right: 14,
                  child: _CoverButton(
                    busy: _coverUploading,
                    hasCover: _coverUrl != null,
                    onTap: _coverMenu,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(child: _avatar(dark, avatarR)),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(side, 12, side, 0),
            child: Column(
              children: [
                _identity(context),
                const SizedBox(height: 16),
                _statsStrip(context, dark),
                const SizedBox(height: 12),
                _modeCard(context, dark),
                const SizedBox(height: 8),
                ..._sections(context, dark),
                _footer(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PC: sticky identity card left, everything you can do right ─────
  Widget _wideLayout(
      BuildContext context, bool studio, bool dark, double width) {
    final theme = Theme.of(context);
    const bandH = 128.0;
    const avatarR = 46.0;
    return SafeArea(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: width >= 1300 ? 390 : 350,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 32),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: bandH + avatarR + 8,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: bandH,
                              child: _coverBand(studio, height: bandH)),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: _CoverButton(
                              busy: _coverUploading,
                              hasCover: _coverUrl != null,
                              onTap: _coverMenu,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Center(child: _avatar(dark, avatarR)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                      child: Column(
                        children: [
                          _identity(context),
                          const SizedBox(height: 16),
                          _statsStrip(context, dark),
                          const SizedBox(height: 12),
                          _modeCard(context, dark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 20, 28, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your space',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Everything you read, write and own on BookNest.',
                        style: TextStyle(color: theme.hintColor)),
                    ..._sections(context, dark),
                    Center(child: _footer(context)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────

  Widget _avatar(bool dark, double radius) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _avatarUrl == null
              ? _changeAvatar
              : () => openChatPhoto(context, _avatarUrl!,
                  album: [MediaItem(url: _avatarUrl!, name: _displayName)]),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [BookNestColors.cyan, BookNestColors.navy],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                  color:
                      dark ? BookNestColors.darkChatBackground : Colors.white,
                  width: 3),
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: BookNestColors.navy,
              backgroundImage:
                  _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
              child: _avatarUrl == null
                  ? Text(
                      _displayName.characters.isEmpty
                          ? '?'
                          : _displayName.characters.first.toUpperCase(),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: radius * .66,
                          fontWeight: FontWeight.w800),
                    )
                  : null,
            ),
          ),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Tooltip(
            message: 'Change profile photo',
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
        ),
      ],
    );
  }

  /// Name (tap to edit), Author mark, flag, handle, email, moderator chip.
  Widget _identity(BuildContext context) {
    final theme = Theme.of(context);
    final code = ReaderProfile.instance.countryCode ?? '';
    final flag = code.isEmpty ? null : flagForCountry(code);
    final username = _profile?['username']?.toString() ?? '';
    return Column(
      children: [
        InkWell(
          onTap: _editDisplayName,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  _displayName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Icon(Icons.edit_rounded,
                    size: 17, color: BookNestColors.cyan),
                if (_mode == 'author') _authorMark(),
              ],
            ),
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            if (flag != null && flag.isNotEmpty)
              Tooltip(
                message: countryNameFor(code) ?? 'Country',
                triggerMode: TooltipTriggerMode.tap,
                child: Text(flag, style: const TextStyle(fontSize: 18)),
              ),
            if (username.isNotEmpty)
              Text('@$username',
                  style: const TextStyle(
                      color: BookNestColors.cyan,
                      fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        Text(_email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.hintColor, fontSize: 13)),
        if (_isOverallModerator) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: BookNestColors.cyan.withOpacity(.14),
              border: Border.all(color: BookNestColors.cyan.withOpacity(.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_rounded,
                    size: 15, color: BookNestColors.cyan),
                SizedBox(width: 6),
                Text('Overall moderator',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: BookNestColors.cyan)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _authorMark() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: BookNestColors.cyan.withOpacity(.14),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_edu_rounded,
                size: 13, color: BookNestColors.cyan),
            SizedBox(width: 4),
            Text('Author',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: BookNestColors.cyan)),
          ],
        ),
      );

  /// Gems · mode · sync — three tappable cells in one rounded strip.
  Widget _statsStrip(BuildContext context, bool dark) {
    final theme = Theme.of(context);
    final online = _cloudStatus == 'online';
    Widget cell(IconData icon, String value, String label, VoidCallback onTap,
        {Color? color}) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color ?? BookNestColors.cyan),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: theme.hintColor,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: BookNestColors.cyan.withOpacity(.08),
        border: Border.all(color: BookNestColors.cyan.withOpacity(.28)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            cell(Icons.diamond_rounded, '${_profile?['gems'] ?? 0}', 'Gems',
                () => context.push('/wallet')),
            VerticalDivider(
                width: 1, color: BookNestColors.cyan.withOpacity(.22)),
            cell(
                _mode == 'author'
                    ? Icons.history_edu_rounded
                    : Icons.auto_stories_rounded,
                _mode == 'author' ? 'Author' : 'Reader',
                'Mode',
                _modeBusy ? () {} : _switchMode),
            VerticalDivider(
                width: 1, color: BookNestColors.cyan.withOpacity(.22)),
            cell(
                online
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                _cloudStatus == null
                    ? '…'
                    : online
                        ? 'Synced'
                        : 'Offline',
                'Cloud',
                _probeCloud,
                color: online ? BookNestColors.cyan : theme.hintColor),
          ],
        ),
      ),
    );
  }

  /// The Author / Reader switch — BookNest's answer to Facebook's
  /// profile-mode toggle.
  Widget _modeCard(BuildContext context, bool dark) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _modeBusy ? null : _switchMode,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: dark
              ? Colors.white.withOpacity(.05)
              : BookNestColors.navyDeep.withOpacity(.04),
          border: Border.all(color: BookNestColors.cyan.withOpacity(.35)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BookNestColors.cyan.withOpacity(.15),
              ),
              child: Icon(
                _mode == 'author'
                    ? Icons.history_edu_rounded
                    : Icons.auto_stories_rounded,
                color: BookNestColors.cyan,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mode == 'author'
                        ? 'Author mode is on'
                        : 'Reader mode is on',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _mode == 'author'
                        ? 'Writing tools lead your profile — tap to switch '
                            'back to Reader'
                        : 'Switch to Author to put your books, studio and '
                            'stats front and centre',
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: BookNestColors.cyan,
              ),
              child: _modeBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: BookNestColors.navyDeep))
                  : Text(
                      _mode == 'author' ? 'Reader' : 'Author',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: BookNestColors.navyDeep),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Every destination, grouped. Tiles flow into as many columns as the
  /// width allows (2 on a phone, 3–4 on PC); Account stays a list.
  List<Widget> _sections(BuildContext context, bool dark) {
    final author = _mode == 'author';
    final writing = <_ProfileTile>[
      _ProfileTile(Icons.edit_note_rounded, 'New book',
          'Open the manuscript studio', () => context.push('/editor')),
      _ProfileTile(Icons.dashboard_rounded, 'Writer dashboard',
          'Your books at a glance', () => context.push('/dashboard')),
      _ProfileTile(Icons.insights_rounded, 'Reviews hub',
          'What readers say about your books',
          () => context.push('/reviews-hub')),
    ];
    final everyday = <_ProfileTile>[
      _ProfileTile(Icons.forum_rounded, 'Messages', 'Your conversations',
          () => context.go('/dms')),
      _ProfileTile(Icons.menu_book_rounded, 'My library',
          'Books you love and write', () => context.push('/library')),
      if (!author)
        _ProfileTile(Icons.dashboard_rounded, 'Writer dashboard',
            'Manage your books and chapters',
            () => context.push('/dashboard')),
      _ProfileTile(Icons.person_outline_rounded, 'Public profile',
          'See what readers see', () => context.push('/user/$_viewerId')),
      _ProfileTile(Icons.diamond_outlined, 'Gems wallet',
          'Balance, daily bonus and activity', () => context.push('/wallet')),
      if (AppConfig.jennyEnabled)
        _ProfileTile(Icons.auto_awesome_rounded, 'Ask Jenny',
            'Your AI reading companion', () => context.push('/jenny')),
      _ProfileTile(Icons.event_note_rounded, 'Events agenda',
          'Every event, RSVPs and reminders', () => context.push('/events')),
      _ProfileTile(Icons.local_fire_department_rounded, 'Reading streaks',
          'Log your days, keep the flame alive',
          () => context.push('/streaks')),
      _ProfileTile(Icons.notifications_none_rounded, 'Notifications',
          'Messages and activity', () => context.push('/notifications')),
    ];
    return [
      if (author) ...[
        _sectionLabel(context, 'WRITING'),
        _tileGrid(writing),
      ],
      _sectionLabel(context, 'YOUR BOOKNEST'),
      _tileGrid(everyday),
      _sectionLabel(context, 'ACCOUNT'),
      if (_isOverallModerator)
        _ProfileAction(
          icon: Icons.admin_panel_settings_rounded,
          label: 'Moderation console',
          subtitle: 'Reports, deletions, community safety',
          onTap: () => context.push('/moderation'),
        ),
      _ProfileAction(
        icon: Icons.settings_rounded,
        label: 'Settings',
        subtitle: 'Theme, privacy and more',
        onTap: () => context.push('/settings'),
      ),
      _ProfileAction(
        icon: Icons.logout_rounded,
        label: 'Sign out',
        subtitle: _email,
        danger: true,
        onTap: _signOut,
      ),
    ];
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).hintColor)),
        ),
      );

  Widget _tileGrid(List<_ProfileTile> tiles) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 10.0;
      final cols = c.maxWidth < 290 ? 1 : (c.maxWidth / 220).floor().clamp(2, 4);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }

  Widget _footer(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          children: [
            _CloudStatusChip(status: _cloudStatus, onRetry: _probeCloud),
            const SizedBox(height: 12),
            Text(
              'BookNest ${AppConfig.appVersion} · by N.O Group',
              style: TextStyle(
                  color: Theme.of(context).hintColor, fontSize: 12),
            ),
          ],
        ),
      );
}

/// A square-ish destination card for the profile grid.
class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileTile(this.icon, this.label, this.subtitle, this.onTap);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: theme.dividerColor.withOpacity(.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: BookNestColors.cyan.withOpacity(.12),
                ),
                child: Icon(icon, color: BookNestColors.cyan, size: 20),
              ),
              const Spacer(),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.hintColor, fontSize: 11.5)),
            ],
          ),
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

/// Small pill that shows whether the booknest-api cloud backend is live.
/// Tap it to re-check. 'offline' is normal until the edge function is
/// deployed from the Supabase dashboard (backend/DEPLOY_FROM_DASHBOARD.md).
class _CloudStatusChip extends StatelessWidget {
  final String? status;
  final VoidCallback onRetry;

  const _CloudStatusChip({required this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = status == 'online';
    final checking = status == null;
    final color = checking
        ? theme.hintColor
        : online
            ? BookNestColors.cyan
            : theme.hintColor;
    final label = checking
        ? 'Connecting…'
        : online
            ? 'Synced ✓'
            : 'Offline · tap to retry';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: online
              ? BookNestColors.cyan.withOpacity(.12)
              : theme.colorScheme.surface,
          border: Border.all(
            color: online ? BookNestColors.cyan.withOpacity(.45) : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: online
                    ? (theme.brightness == Brightness.dark
                        ? BookNestColors.darkTextPrimary
                        : BookNestColors.navyDeep)
                    : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _CoverButton extends StatelessWidget {
  final bool busy;
  final bool hasCover;
  final VoidCallback onTap;
  const _CoverButton(
      {required this.busy, required this.hasCover, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(.38),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
              else
                const Icon(Icons.add_photo_alternate_rounded,
                    size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(hasCover ? 'Edit cover' : 'Add cover photo',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
