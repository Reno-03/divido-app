import 'package:divido_app/constants/color_options.dart';
import 'package:flutter/material.dart';
import 'package:divido_app/services/current_user.dart';
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
        title: const Text('Profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _showEditModal,
            ),
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),

            // Avatar
            CircleAvatar(
              radius: 48,
              backgroundColor: userColor,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
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
            _infoTile(
              Icons.phone_outlined,
              'Contact',
              user.contactNumber ?? '—',
            ),
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
}
