import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/theme.dart';
import '../../../services/supabase_service.dart';

/// Registration screen with an **optional** profile photo.
///
/// The photo is picked before sign-up, uploaded to the `avatars` Storage
/// bucket right after the account is created (original/HD quality), and the
/// `profiles` row is created for the new user.
///
/// If the Supabase project requires email confirmation, sign-up returns no
/// session yet — we show an info message and stay on the screen (the profile
/// row is created lazily on first login via `ensureProfileForCurrentUser`).
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
  Uint8List? _avatarBytes;
  bool _isLoading = false;

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // No imageQuality/maxWidth: keep the original (HD) photo.
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _avatarBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not pick a photo.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _signUp() async {
    if (_usernameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _phoneController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = SupabaseService();
      final res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {
          'username': _usernameController.text.trim(),
          'phone': _phoneController.text.trim(),
        },
      );

      if (!mounted) return;

      if (res.session == null) {
        // Email confirmation is required — there is no session yet. Do NOT
        // navigate to the feed: the router would treat the user as signed out
        // and bounce them back here on every protected action.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created! Check your email to confirm, then log in.',
            ),
            backgroundColor: Color(0xFF1E4FD6),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Session exists — create the profile row and upload the optional photo.
      await supabase.ensureProfileForCurrentUser();

      if (_avatarBytes != null) {
        final url = await supabase.uploadPublicImage(
          bucket: 'avatars',
          path: '${res.session!.user.id}.jpg',
          bytes: _avatarBytes!,
          contentType: 'image/jpeg',
        );
        await supabase.client
            .from('profiles')
            .update({'avatar_url': url}).eq('id', res.session!.user.id);
      }

      if (!mounted) return;
      context.go('/feed');
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NOC.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                 Text(
                  'Create account',
                  style: TextStyle(
                    color: NOC.text,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join the bookworm community',
                  style: TextStyle(color: NOC.textMuted, fontSize: 16),
                ),
                const SizedBox(height: 24),

                // Optional profile photo
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: NOC.surfaceAlt,
                            border: Border.all(color: NOC.accent, width: 2),
                          ),
                          child: _avatarBytes != null
                              ? ClipOval(
                                  child: Image.memory(
                                    _avatarBytes!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  Icons.add_a_photo_outlined,
                                  color: NOC.accent,
                                  size: 32,
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add profile photo (optional)',
                          style: TextStyle(color: NOC.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                _buildTextField(
                  controller: _usernameController,
                  hintText: 'Username',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _emailController,
                  hintText: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  hintText: 'Phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passwordController,
                  hintText: 'Password',
                  obscureText: true,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient:  LinearGradient(
                        colors: [Color(0xFF1E4FD6), NOC.accent],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ?  CircularProgressIndicator(color: NOC.onAccent)
                          :  Text(
                              'Sign Up',
                              style: TextStyle(
                                color: NOC.onAccent,
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
                    Text(
                      'Already have an account? ',
                      style: TextStyle(color: NOC.textMuted),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        'Log in',
                        style: TextStyle(
                          color: NOC.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: NOC.text),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: NOC.textFaint),
        filled: true,
        fillColor: NOC.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      ),
    );
  }
}
