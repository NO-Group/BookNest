// lib/presentation/screens/auth/register_screen.dart
//
// Two-step signup:
//   1. Account — email / password / username / phone.
//   2. Profile — optional photo + display name (skippable). Only reached
//      with a live session. If the project requires email confirmation we
//      show a "check your inbox" step instead of entering the app without
//      a session (which previously caused permission errors on every write).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/theme.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/supabase_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();

  Uint8List? _avatarBytes;
  String _avatarExtension = 'jpg';
  bool _isLoading = false;
  bool _obscure = true;
  bool _awaitingConfirmation = false;

  String get _username =>
      _usernameController.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ── step 1 · account ───────────────────────────────────────────────────────
  Future<void> _signUp() async {
    if (_usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      _toast('Please fill in all fields');
      return;
    }
    if (_passwordController.text.trim().length < 6) {
      _toast('Password needs at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await SupabaseService().auth.signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            data: {
              'username': _username,
              'phone': _phoneController.text.trim(),
            },
          );

      if (!mounted) return;
      if (res.session == null) {
        // Email confirmation required — never enter the app unauthenticated.
        setState(() {
          _awaitingConfirmation = true;
          _isLoading = false;
        });
        return;
      }
      // Session is live: create the profile row right away so this reader is
      // discoverable in chat + search from day one.
      try {
        await SupabaseService().createProfile(
          userId: res.user!.id,
          username: _username,
          phoneNumber: _phoneController.text.trim(),
        );
      } catch (e) {
        _toast('Profile row: ${e.toString().split('\n').first}');
      }
      _displayNameController.text = _username;
      setState(() => _isLoading = false);
      _profileStepActive = true;
      setState(() {});
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _toast(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _toast('An unexpected error occurred: $e');
      }
    }
  }

  bool _profileStepActive = false;

  // ── step 2 · profile (optional photo) ──────────────────────────────────────
  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final extension =
          file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
      setState(() {
        _avatarBytes = bytes;
        _avatarExtension = extension;
      });
    } catch (_) {
      _toast('Could not open the photo picker on this device.');
    }
  }

  Future<void> _finishProfile({required bool skipping}) async {
    if (skipping) {
      if (mounted) context.go('/onboarding');
      return;
    }
    setState(() => _isLoading = true);
    final user = SupabaseService().auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }
    final displayName = _displayNameController.text.trim();
    if (displayName.isNotEmpty && displayName != _username) {
      try {
        await SupabaseService().updateRow(
          'profiles',
          {'display_name': displayName},
          column: 'id',
          equals: user.id,
        );
      } on WriteException catch (e) {
        _toast(e.message);
      } catch (_) {}
    }
    if (_avatarBytes != null) {
      final url = await CloudinaryService.uploadImage(
        bytes: _avatarBytes!,
        folder: 'avatars',
        publicId:
            'avatar-${user.id}-${DateTime.now().millisecondsSinceEpoch}',
        extension: _avatarExtension,
      );
      if (url != null) {
        try {
          await SupabaseService().updateRow(
            'profiles',
            {'avatar_url': url},
            column: 'id',
            equals: user.id,
          );
        } on WriteException catch (e) {
          _toast(e.message);
        } catch (_) {}
      }
    }
    if (mounted) context.go('/onboarding');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BookNestColors.navyDeep.withOpacity(.12),
              theme.scaffoldBackgroundColor,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _awaitingConfirmation
                    ? _buildConfirmation(theme)
                    : _profileStepActive
                        ? _buildProfileStep(theme, onSurface)
                        : _buildAccountForm(theme, onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── confirmation view ──────────────────────────────────────────────────────
  Widget _buildConfirmation(ThemeData theme) {
    return Column(
      key: const ValueKey('confirm'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BookNestColors.cyan.withOpacity(.14),
            border: Border.all(color: BookNestColors.cyan.withOpacity(.5)),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              color: BookNestColors.cyan, size: 42),
        ),
        const SizedBox(height: 24),
        Text('Check your inbox',
            style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(
          'We sent a confirmation link to\n${_emailController.text.trim()}.\n'
          'Confirm it, then log in to finish setting up your profile.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => context.go('/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: BookNestColors.cyan,
              foregroundColor: BookNestColors.navyDeep,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Go to log in',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          ),
        ),
      ],
    );
  }

  // ── step 2 · profile ───────────────────────────────────────────────────────
  Widget _buildProfileStep(ThemeData theme, Color onSurface) {
    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set up your profile',
            style: TextStyle(
                color: onSurface, fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Add a face to your bookshelf — totally optional.',
            style: TextStyle(color: theme.hintColor, fontSize: 15)),
        const SizedBox(height: 32),
        Center(
          child: GestureDetector(
            onTap: _isLoading ? null : _pickAvatar,
            child: Stack(
              children: [
                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surface,
                    image: _avatarBytes != null
                        ? DecorationImage(
                            image: MemoryImage(_avatarBytes!),
                            fit: BoxFit.cover)
                        : null,
                    border: Border.all(
                        color: BookNestColors.cyan.withOpacity(.6), width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: BookNestColors.cyan.withOpacity(.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: _avatarBytes == null
                      ? Icon(Icons.person_add_alt_1_rounded,
                          size: 42,
                          color: theme.hintColor)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BookNestColors.cyan,
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 17, color: BookNestColors.navyDeep),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        _buildTextField(
            controller: _displayNameController, hintText: 'Display name'),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () => _finishProfile(skipping: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: BookNestColors.cyan,
              foregroundColor: BookNestColors.navyDeep,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: BookNestColors.navyDeep))
                : const Text('Continue',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: _isLoading ? null : () => _finishProfile(skipping: true),
            child: Text('Skip for now',
                style: TextStyle(color: theme.hintColor, fontSize: 14.5)),
          ),
        ),
      ],
    );
  }

  // ── step 1 · account form ──────────────────────────────────────────────────
  Widget _buildAccountForm(ThemeData theme, Color onSurface) {
    return Column(
      key: const ValueKey('account'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Create account',
          style: TextStyle(
            color: onSurface,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Join the bookworm community',
          style: TextStyle(color: theme.hintColor, fontSize: 16),
        ),
        const SizedBox(height: 32),
        _buildTextField(
            controller: _usernameController, hintText: 'Username'),
        const SizedBox(height: 16),
        _buildTextField(
            controller: _emailController,
            hintText: 'Email address',
            keyboardType: TextInputType.emailAddress),
        const SizedBox(height: 16),
        _buildTextField(
            controller: _phoneController,
            hintText: 'Phone number',
            keyboardType: TextInputType.phone),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          obscureText: _obscure,
          suffix: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: theme.hintColor,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [BookNestColors.cyanSoft, BookNestColors.cyan],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: BookNestColors.cyan.withOpacity(.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: BookNestColors.navyDeep)
                  : const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: BookNestColors.navyDeep,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already have an account? ',
                style: TextStyle(color: theme.hintColor)),
            GestureDetector(
              onTap: () => context.go('/login'),
              child: const Text(
                'Log in',
                style: TextStyle(
                    color: BookNestColors.cyan,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: theme.hintColor),
        suffixIcon: suffix,
        filled: true,
        fillColor: theme.colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: BookNestColors.cyan, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      ),
    );
  }
}
