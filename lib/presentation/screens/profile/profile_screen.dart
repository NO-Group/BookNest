import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/theme_controller.dart';
import '../../../core/utils/time_format.dart';
import '../../../services/supabase_service.dart';
import '../../components/user_avatar.dart';
import '../../../config/theme.dart';

/// Profile tab (Tab 5 of the bottom nav).
///
/// Shows the signed-in user's profile: avatar, name, username, bio and gem
/// balance, plus their authored books and posts. The profile row itself is
/// streamed live, so edits made in the edit sheet appear immediately.
/// Signing out clears the session and returns to `/login`.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _myId;

  Stream<List<Map<String, dynamic>>>? _profileStream;
  Map<String, dynamic>? _profile;
  bool _profileLoading = true;

  final List<Map<String, dynamic>> _books = [];
  bool _booksLoading = true;

  final List<Map<String, dynamic>> _drafts = [];
  bool _draftsLoading = true;

  final List<Map<String, dynamic>> _posts = [];
  bool _postsLoading = true;

  @override
  void initState() {
    super.initState();
    _myId = SupabaseService().auth.currentUser?.id;
    if (_myId == null) return;

    _profileStream = SupabaseService()
        .client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', _myId!)
        .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());

    _loadBooks();
    _loadDrafts();
    _loadPosts();
  }

  Future<void> _loadBooks() async {
    try {
      final res = await SupabaseService()
          .client
          .from('club_books')
          .select('id, title, description, moderation_status, created_at')
          .eq('added_by', _myId!)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _books
          ..clear()
          ..addAll(res.map((r) => Map<String, dynamic>.from(r)).toList());
        _booksLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _booksLoading = false);
    }
  }

  Future<void> _loadDrafts() async {
    try {
      final res = await SupabaseService()
          .client
          .from('club_books')
          .select('id, title, description, community_id, created_at')
          .eq('added_by', _myId!)
          .eq('moderation_status', 'draft')
          .or('community_id.is.null')
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _drafts
          ..clear()
          ..addAll(res.map((r) => Map<String, dynamic>.from(r)).toList());
        _draftsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _draftsLoading = false);
    }
  }

  Future<void> _deleteDraft(String bookId) async {
    try {
      await SupabaseService().client.from('club_books').delete().eq('id', bookId);
      if (!mounted) return;
      setState(() => _loadDrafts());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete draft: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _loadPosts() async {
    try {
      final res = await SupabaseService()
          .client
          .from('posts')
          .select('id, type, title, content, created_at')
          .eq('created_by', _myId!)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(res.map((r) => Map<String, dynamic>.from(r)).toList());
        _postsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _postsLoading = false);
    }
  }

  Future<void> _openEditSheet() async {
    final profile = _profile;
    if (profile == null) return;

    final displayNameController =
        TextEditingController(text: profile['display_name']?.toString() ?? '');
    final usernameController =
        TextEditingController(text: profile['username']?.toString() ?? '');
    final bioController =
        TextEditingController(text: profile['bio']?.toString() ?? '');
    final avatarController =
        TextEditingController(text: profile['avatar_url']?.toString() ?? '');
    bool saving = false;
    bool uploadingAvatar = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NOC.surfaceAlt,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickAndUploadAvatar() async {
              try {
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  // No imageQuality/maxWidth => the original HD image is uploaded.
                );
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                setSheetState(() => uploadingAvatar = true);
                final url = await SupabaseService().uploadPublicImage(
                  bucket: 'avatars',
                  path: '${_myId ?? 'user'}.jpg',
                  bytes: bytes,
                  contentType: 'image/jpeg',
                );
                if (!mounted) return;
                setSheetState(() {
                  avatarController.text = url;
                  uploadingAvatar = false;
                });
              } catch (e) {
                if (!mounted) return;
                setSheetState(() => uploadingAvatar = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not upload photo: $e'), backgroundColor: Colors.redAccent),
                );
              }
            }
            Future<void> save() async {
              final username = usernameController.text.trim();
              if (username.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Username cannot be empty.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }
              setSheetState(() => saving = true);
              try {
                await SupabaseService()
                    .client
                    .from('profiles')
                    .update({
                      'display_name': displayNameController.text.trim(),
                      'username': username,
                      'bio': bioController.text.trim(),
                      'avatar_url': avatarController.text.trim(),
                    })
                    .eq('id', _myId!);
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                if (!context.mounted) return;
                setSheetState(() => saving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not save: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                        'Edit profile',
                        style: TextStyle(
                          color: NOC.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildField(
                        controller: displayNameController,
                        label: 'Display name',
                        hint: 'How your name appears',
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: usernameController,
                        label: 'Username',
                        hint: '@username',
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: bioController,
                        label: 'Bio',
                        hint: 'A short line about you',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                       Text(
                        'Profile photo',
                        style: TextStyle(color: NOC.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: uploadingAvatar ? null : pickAndUploadAvatar,
                          icon: uploadingAvatar
                              ?  SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: NOC.accent,
                                  ),
                                )
                              : const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Choose from gallery'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NOC.accent,
                            side:  BorderSide(color: NOC.accent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: avatarController,
                        label: 'Avatar URL (optional override)',
                        hint: 'https://... (image link)',
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: saving ? null : save,
                          child: saving
                              ?  SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: NOC.text,
                                  ),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    displayNameController.dispose();
    usernameController.dispose();
    bioController.dispose();
    avatarController.dispose();
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style:  TextStyle(color: NOC.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style:  TextStyle(color: NOC.text, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:  TextStyle(color: NOC.textFaint),
            filled: true,
            fillColor: NOC.surfaceAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NOC.surfaceAlt,
        title:  Text(
          'Sign out?',
          style: TextStyle(color: NOC.text, fontSize: 18),
        ),
        content:  Text(
          'You will need to sign in again to publish and chat.',
          style: TextStyle(color: NOC.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await SupabaseService().auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      appBar: AppBar(title: const Text('Profile')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_myId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Icon(
              Icons.lock_outline,
              size: 56,
              color: NOC.textFaint,
            ),
            const SizedBox(height: 16),
             Text(
              'Sign in to view your profile',
              style: TextStyle(color: NOC.text, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Sign in'),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          _profile = snapshot.data!.first;
          if (_profileLoading) _profileLoading = false;
        }

        final profile = _profile;
        if (profile == null && _profileLoading) {
          return  Center(
            child: CircularProgressIndicator(color: NOC.accent),
          );
        }

        return RefreshIndicator(
          color: NOC.accent,
          backgroundColor: NOC.surface,
          onRefresh: () async {
            await Future.wait([_loadBooks(), _loadDrafts(), _loadPosts()]);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              _buildHeader(profile),
              const SizedBox(height: 20),
              _buildStats(profile),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _openEditSheet,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NOC.accent,
                  side:  BorderSide(color: NOC.accent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
              const SizedBox(height: 28),
              _buildThemeSection(),
              const SizedBox(height: 28),
               Text(
                'My Drafts',
                style: TextStyle(
                  color: NOC.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildDraftsSection(),
              const SizedBox(height: 28),
               Text(
                'My Books',
                style: TextStyle(
                  color: NOC.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildBooksSection(),
              const SizedBox(height: 28),
               Text(
                'My Posts',
                style: TextStyle(
                  color: NOC.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildPostsSection(),
              const SizedBox(height: 28),
               Divider(color: NOC.border),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Colors.redAccent),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.redAccent, fontSize: 15),
                ),
                onTap: _signOut,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic>? profile) {
    final displayName = profile?['display_name']?.toString() ?? 'Reader';
    final username = profile?['username']?.toString() ?? 'reader';
    final bio = profile?['bio']?.toString() ?? '';
    final gems = (profile?['gems'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        const SizedBox(height: 8),
        UserAvatar(
          imageUrl: profile?['avatar_url']?.toString(),
          name: displayName,
          radius: 44,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:  TextStyle(
                  color: NOC.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (gems > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: NOC.gold.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Icon(
                      Icons.diamond,
                      size: 14,
                      color: NOC.gold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$gems',
                      style:  TextStyle(
                        color: NOC.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '@$username',
          style:  TextStyle(color: NOC.textMuted, fontSize: 14),
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            bio,
            textAlign: TextAlign.center,
            style:  TextStyle(
              color: NOC.textMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        if (profile?['created_at'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Joined ${formatFullDate(profile?['created_at'])}',
            style:  TextStyle(color: NOC.textFaint, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildStats(Map<String, dynamic>? profile) {
    final gems = (profile?['gems'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: NOC.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NOC.border),
      ),
      child: Row(
        children: [
          _buildStatItem(label: 'Books', value: _books.length),
          _buildDivider(),
          _buildStatItem(label: 'Posts', value: _posts.length),
          _buildDivider(),
          _buildStatItem(label: 'Gems', value: gems),
        ],
      ),
    );
  }

  Widget _buildStatItem({required String label, required int value}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style:  TextStyle(
              color: NOC.text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style:  TextStyle(color: NOC.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 30, color: NOC.border);
  }

  Widget _buildDraftsSection() {
    if (_draftsLoading) {
      return  Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: NOC.accent),
        ),
      );
    }
    if (_drafts.isEmpty) {
      return  Text(
        'No drafts yet — save a book from the editor to keep it here.',
        style: TextStyle(color: NOC.textMuted, fontSize: 13),
      );
    }
    return Column(
      children: _drafts.map((draft) {
        final title = draft['title']?.toString() ?? 'Untitled';
        final bookId = draft['id']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NOC.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NOC.gold.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: NOC.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:  Icon(Icons.edit_note, color: NOC.gold, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:  TextStyle(
                        color: NOC.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Saved ${formatFullDate(draft['created_at'])}',
                      style:  TextStyle(color: NOC.textFaint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon:  Icon(Icons.edit_outlined, color: NOC.accent, size: 20),
                tooltip: 'Continue writing',
                onPressed: () => context.push('/editor?bookId=$bookId'),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete draft',
                onPressed: () => _deleteDraft(bookId),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildThemeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Text(
          'Theme',
          style: TextStyle(
            color: NOC.text,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) {
            return SegmentedButton<AppThemeMode>(
              segments: AppThemeMode.values
                  .map((mode) => ButtonSegment(
                        value: mode,
                        icon: Icon(
                          switch (mode) {
                            AppThemeMode.system => Icons.brightness_auto,
                            AppThemeMode.light => Icons.light_mode_outlined,
                            AppThemeMode.dark => Icons.dark_mode_outlined,
                          },
                          size: 18,
                        ),
                        label: Text(mode.label),
                      ))
                  .toList(),
              selected: {themeController.mode},
              onSelectionChanged: (selection) =>
                  themeController.setMode(selection.first),
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? NOC.accent
                        : NOC.surfaceAlt),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? NOC.onAccent
                        : NOC.text),
                side: WidgetStatePropertyAll(
                  BorderSide(color: NOC.border),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBooksSection() {
    if (_booksLoading) {
      return  Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: NOC.accent),
        ),
      );
    }
    if (_books.isEmpty) {
      return  Text(
        'You have not published any books yet.',
        style: TextStyle(color: NOC.textMuted, fontSize: 13),
      );
    }
    return Column(
      children: _books.map((book) {
        final title = book['title']?.toString() ?? 'Untitled';
        final status = book['moderation_status']?.toString() ?? 'pending';
        final isApproved = status == 'approved';
        final bookId = book['id']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NOC.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NOC.border),
          ),
          child: InkWell(
            onTap: () => context.push('/publish-details?bookId=$bookId'),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NOC.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:  Icon(
                    Icons.menu_book,
                    color: NOC.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:  TextStyle(
                          color: NOC.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatFullDate(book['created_at']),
                        style:  TextStyle(
                          color: NOC.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isApproved
                        ? NOC.accent.withOpacity(0.12)
                        : NOC.hot.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isApproved ? 'Approved' : 'Pending',
                    style: TextStyle(
                      color: isApproved
                          ? NOC.accent
                          : NOC.hot,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPostsSection() {
    if (_postsLoading) {
      return  Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: NOC.accent),
        ),
      );
    }
    if (_posts.isEmpty) {
      return  Text(
        'You have not posted anything yet.',
        style: TextStyle(color: NOC.textMuted, fontSize: 13),
      );
    }
    return Column(
      children: _posts.map((post) {
        final type = post['type']?.toString() ?? 'text';
        final preview = (post['content']?.toString() ?? '').isNotEmpty
            ? post['content'].toString()
            : (post['title']?.toString() ?? '');
        final isQuote = type == 'quote';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NOC.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NOC.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: NOC.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type.toUpperCase(),
                  style:  TextStyle(
                    color: NOC.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isQuote ? '"$preview"' : preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:  TextStyle(
                  color: NOC.textMuted,
                  fontSize: 13,
                  height: 1.4,
                  fontStyle: isQuote ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                formatFullDate(post['created_at']),
                style:  TextStyle(color: NOC.textFaint, fontSize: 11),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
