import 'package:divido_app/constants/color_options.dart';
import 'package:divido_app/providers/expense_provider.dart';
import 'package:flutter/material.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  void _showEditModal() {
    final user = CurrentUser.instance;
    final firstNameController = TextEditingController(text: user.firstname);
    final lastNameController = TextEditingController(text: user.lastname);
    final usernameController = TextEditingController(text: user.username);
    final contactController = TextEditingController(text: user.contactNumber);
    bool isSaving = false;

    // get current user color
    final rawColor = user.color ?? '#6366F1';
    Color selectedColor = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom +
                20, // 👈 moves form above keyboard
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _editField(
                firstNameController,
                'First Name',
                Icons.badge_outlined,
              ),
              const SizedBox(height: 24),
              _editField(lastNameController, 'Last Name', Icons.badge_outlined),
              const SizedBox(height: 24),
              _editField(usernameController, 'Username', Icons.person_outline),
              const SizedBox(height: 24),
              _editField(
                contactController,
                'Contact Number',
                Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),

              const Text(
                'Pick your color:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: kColorOptions.map((color) {
                  final isSelected = selectedColor == color;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedColor = color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setModalState(() => isSaving = true);

                          await Supabase.instance.client
                              .from('profiles')
                              .update({
                                'firstname': firstNameController.text.trim(),
                                'lastname': lastNameController.text.trim(),
                                'username': usernameController.text.trim(),
                                'contact_number': contactController.text.trim(),
                                'color':
                                    '#${selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                              })
                              .eq('id', CurrentUser.instance.id!);

                          // Update local user
                          CurrentUser.instance.firstname = firstNameController
                              .text
                              .trim();
                          CurrentUser.instance.lastname = lastNameController
                              .text
                              .trim();
                          CurrentUser.instance.username = usernameController
                              .text
                              .trim();
                          CurrentUser.instance.contactNumber = contactController
                              .text
                              .trim();
                          CurrentUser.instance.color =
                              '#${selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

                          if (ctx.mounted) Navigator.pop(ctx);

                          // refresh expenses so owner name updates in AllPage
                          Provider.of<ExpenseProvider>(
                            context,
                            listen: false,
                          ).refresh();

                          setState(() {}); // refresh ProfilePage
                        },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gcashPill(bool isReady) {
    final color = isReady ? Colors.green : Colors.red;

    return GestureDetector(
      onTap: () async {
        final newValue = !isReady;

        // 1. Update UI instantly
        CurrentUser.instance.isGcashReady = newValue;
        setState(() {});

        // 2. Sync to Supabase in background
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'is_gcash_ready': newValue})
              .eq('id', CurrentUser.instance.id!);
        } catch (e) {
          // Revert on failure
          CurrentUser.instance.isGcashReady = isReady;
          setState(() {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update GCash status.')),
            );
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isReady ? const Color(0xFFE8FFF3) : const Color(0xFFFFECEC),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isReady
                ? Colors.green.withValues(alpha: 0.4)
                : Colors.red.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/gcash_logo.png',
              width: 20,
              height: 20,
              fit: BoxFit.cover,
            ),
            const SizedBox(width: 8),
            Icon(
              isReady ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  void _showStatusDialog() {
    final controller = TextEditingController(
      text: CurrentUser.instance.status ?? '',
    );
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Set Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: 'e.g. Pay me via GCash 😄',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.blue,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  // Clear button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              await Supabase.instance.client
                                  .from('profiles')
                                  .update({'status': null})
                                  .eq('id', CurrentUser.instance.id!);
                              CurrentUser.instance.status = null;
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {});
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Save button
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              final newStatus = controller.text.trim();
                              await Supabase.instance.client
                                  .from('profiles')
                                  .update({
                                    'status': newStatus.isEmpty
                                        ? null
                                        : newStatus,
                                  })
                                  .eq('id', CurrentUser.instance.id!);
                              CurrentUser.instance.status = newStatus.isEmpty
                                  ? null
                                  : newStatus;
                              if (ctx.mounted) Navigator.pop(ctx);
                              setState(() {});
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // Add _pickAndUploadAvatar method to ProfilePage:
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      final userId = CurrentUser.instance.id!;

      // ✅ detect mime from bytes, not from the path
      String contentType = 'image/jpeg'; // safe default
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

      final ext = contentType.split('/').last; // 'jpeg', 'png', etc.
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
        ).showSnackBar(const SnackBar(content: Text('Avatar updated!')));
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  void _showAvatarOptions() {
    final hasAvatar =
        CurrentUser.instance.avatarUrl != null &&
        CurrentUser.instance.avatarUrl!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Profile Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    child: const Icon(Icons.close, size: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Upload / Change
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadAvatar();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        Icons.photo_library_outlined,
                        size: 18,
                        color: Colors.blue.shade300,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      hasAvatar ? 'Change Photo' : 'Upload Photo',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Remove (only if avatar exists)
            if (hasAvatar) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withValues(alpha: 0.15),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Remove Photo',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade400,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        color: Colors.red.withValues(alpha: 0.3),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _removeAvatar() async {
    final userId = CurrentUser.instance.id!;

    try {
      // delete from storage (try both extensions)
      for (final ext in ['jpeg', 'png', 'gif', 'webp']) {
        try {
          await Supabase.instance.client.storage.from('avatars').remove([
            '$userId/avatar.$ext',
          ]);
        } catch (_) {}
      }

      // clear from profiles table
      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': null})
          .eq('id', userId);

      CurrentUser.instance.avatarUrl = null;
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo removed.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to remove photo: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = CurrentUser.instance;

    final rawColor = user.color ?? '#6366F1';
    final userColor = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    final initials =
        '${user.firstname?[0].toUpperCase() ?? ''}${user.lastname?[0].toUpperCase() ?? ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _showEditModal,
            ),
          ),
        ],
      ),

      // NOTE: Instead of Padding, use SingleChildScrollView to make it scrollable
      // because the profile page is now too long
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 1),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Material(
                      color: userColor,
                      child: InkWell(
                        onTap: _showAvatarOptions,
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: CurrentUser.instance.avatarUrl != null
                              ? Image.network(
                                  CurrentUser.instance.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xFF171A3F),
                        width: 2.0,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 14,
                      color: Color(0xFF171A3F),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Status bubble below avatar
            _statusBubble(user.status),
            const SizedBox(height: 16),

            // Full name
            Text(
              '${user.firstname ?? ''} ${user.lastname ?? ''}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Info cards
            _infoTile(Icons.person_outline, 'Username', user.username ?? '—'),
            const SizedBox(height: 12),
            _infoTile(
              Icons.badge_outlined,
              'First Name',
              user.firstname ?? '—',
            ),
            const SizedBox(height: 12),
            _infoTile(Icons.badge_outlined, 'Last Name', user.lastname ?? '—'),
            const SizedBox(height: 12),
            _infoTile(Icons.email_outlined, 'Email', user.email ?? '—'),
            const SizedBox(height: 12),

            // Contact row with GCash pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_outlined,
                    size: 20,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Contact',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const Spacer(),

                  // GCash pill
                  _gcashPill(user.isGcashReady ?? false),
                  const SizedBox(width: 10),

                  Text(
                    user.contactNumber ?? '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            // _infoTile(
            //   Icons.phone_outlined,
            //   'Contact',
            //   user.contactNumber ?? '—',
            // ),
            // const SizedBox(height: 12),
            const SizedBox(height: 12),

            // Color swatch
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.palette_outlined,
                    size: 20,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Color',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: userColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  CurrentUser.instance.clear();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                label: const Text(
                  'Log out',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red[400],
                  padding: const EdgeInsets.symmetric(vertical: 23),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _editField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.2), // 👈 change this
          ),
        ),
      ),
    );
  }

  // this is the widget used as a status bubble below of the Circle Avatar
  Widget _statusBubble(String? status) {
    return GestureDetector(
      onTap: _showStatusDialog,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              size: 16,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status != null && status.isNotEmpty
                    ? status
                    : 'Tap to set a status...',
                style: TextStyle(
                  fontSize: 13,
                  color: status != null && status.isNotEmpty
                      ? Colors.white.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.35),
                  fontStyle: status == null || status.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
