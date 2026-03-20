import 'package:divido_app/services/current_user.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

class AvatarSetupPage extends StatefulWidget {
  const AvatarSetupPage({super.key});

  @override
  State<AvatarSetupPage> createState() => _AvatarSetupPageState();
}

class _AvatarSetupPageState extends State<AvatarSetupPage> {
  bool _isUploading = false;

  final user = CurrentUser.instance;

  String get _initials =>
      '${user.firstname?[0].toUpperCase() ?? ''}${user.lastname?[0].toUpperCase() ?? ''}';

  Color get _userColor {
    final raw = user.color ?? '#6366F1';
    return Color(int.parse('FF${raw.replaceAll('#', '')}', radix: 16));
  }

  Future<void> _pickAndUpload() async {
    if (kIsWeb) {
      final input = web.HTMLInputElement()
        ..type = 'file'
        ..accept = 'image/*';
      input.click();
      await input.onChange.first;
      final files = input.files;
      if (files == null || files.length == 0) return;
      final file = files.item(0)!;
      final arrayBuffer = await file.arrayBuffer().toDart;
      final bytes = Uint8List.view(arrayBuffer.toDart);
      await _upload(bytes, file.type);
    } else {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _upload(bytes, null);
    }
  }

  Future<void> _upload(Uint8List bytes, String? mimeType) async {
    setState(() => _isUploading = true);
    try {
      final userId = user.id!;

      String contentType = mimeType ?? 'image/jpeg';
      if (mimeType == null || mimeType.isEmpty) {
        if (bytes.length >= 4) {
          if (bytes[0] == 0x89 && bytes[1] == 0x50) {
            contentType = 'image/png';
          } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
            contentType = 'image/jpeg';
          } else if (bytes[0] == 0x47 && bytes[1] == 0x49) {
            contentType = 'image/gif';
          } else if (bytes[0] == 0x52 && bytes[1] == 0x49) {
            contentType = 'image/webp';
          }
        }
      }

      final ext = contentType.split('/').last;
      final path = '$userId/avatar.$ext';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );

      final rawUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      final url = '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': rawUrl})
          .eq('id', userId);

      CurrentUser.instance.avatarUrl = url;
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo uploaded!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _continue() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.avatarUrl != null && user.avatarUrl!.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              // title
              const Text(
                'Add a profile photo',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Help your friends recognize you.\nYou can always change this later.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // avatar
              GestureDetector(
                onTap: _isUploading ? null : _pickAndUpload,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // replace the single Container with border + clipBehavior
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.8),
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // color background
                              Container(color: _userColor),

                              // photo or initials
                              hasPhoto
                                  ? Image.network(
                                      user.avatarUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                        child: Text(
                                          _initials,
                                          style: const TextStyle(
                                            fontSize: 40,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        _initials,
                                        style: const TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),

                              // uploading overlay
                              if (_isUploading)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // camera badge
                    if (!_isUploading)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: const Color(0xFF171A3F),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Color(0xFF171A3F),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // choose / change photo button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _pickAndUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF171A3F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF171A3F),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_library_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              hasPhoto ? 'Change Photo' : 'Choose Photo',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // skip / continue button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isUploading ? null : _continue,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: hasPhoto
                          ? Colors.white.withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.15),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    hasPhoto ? 'Continue →' : 'Skip for now',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasPhoto
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: hasPhoto
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
