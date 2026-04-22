import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

import '../providers/group_provider.dart';

const kCardColor = Color(0xFF3C3C63);
const kTileColor = Color(0xFF171A3F);

class GroupInfoPage extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupInfoPage({super.key, required this.group});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  bool _isUploading = false;

  late TextEditingController nameController;
  late TextEditingController descController;

  String? _avatarUrl;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.group['name']);
    descController = TextEditingController(
      text: widget.group['description'] ?? '',
    );

    Future.microtask(() {
      Provider.of<GroupProvider>(
        context,
        listen: false,
      ).fetchGroupMembers(widget.group['id']);
    });

    final url = widget.group['avatar_url'];

    if (url != null) {
      _avatarUrl = '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> _fetchGroup() async {
    final groupId = widget.group['id'];

    final data = await Supabase.instance.client
        .from('groups')
        .select()
        .eq('id', groupId)
        .single();

    setState(() {
      widget.group['avatar_url'] = data['avatar_url'];
      _avatarUrl = data['avatar_url'] != null
          ? '${data['avatar_url']}?v=${DateTime.now().millisecondsSinceEpoch}'
          : null;
    });
  }

  // =========================
  // 📸 IMAGE UPLOAD
  // =========================
  Future<void> _uploadBytes(Uint8List bytes, String? mimeType) async {
    setState(() => _isUploading = true);

    try {
      final groupId = widget.group['id'];

      String contentType = mimeType ?? 'image/jpeg';
      final ext = contentType.split('/').last;

      final path = 'groups/$groupId/avatar.$ext';

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
          .from('groups')
          .update({'avatar_url': rawUrl})
          .eq('id', groupId);

      setState(() {
        widget.group['avatar_url'] = rawUrl;
        _avatarUrl = '$rawUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group photo updated')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      final input = web.HTMLInputElement()
        ..type = 'file'
        ..accept = 'image/*';

      input.click();
      await input.onChange.first;

      final file = input.files?.item(0);
      if (file == null) return;

      final buffer = await file.arrayBuffer().toDart;
      final bytes = Uint8List.view(buffer.toDart);

      await _uploadBytes(bytes, file.type);
      return;
    }

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await _uploadBytes(bytes, null);
  }

  void _showPhotoOptions(bool isMember) {
    if (!isMember) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Group Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.photo_library_outlined),
                    SizedBox(width: 12),
                    Text('Upload / Change Photo'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // 💾 SAVE
  // =========================
  Future<void> _save() async {
    await Supabase.instance.client
        .from('groups')
        .update({
          'name': nameController.text.trim(),
          'description': descController.text.trim(),
        })
        .eq('id', widget.group['id']);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Group updated')));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupProvider>();
    final members = provider.groupMembers;

    final currentUserId = Supabase.instance.client.auth.currentUser!.id;

    final isMember = members.any((m) => m['id'] == currentUserId);

    final creatorId = widget.group['created_by'];

    final sortedMembers = [...members];
    sortedMembers.sort((a, b) {
      if (a['id'] == creatorId) return -1;
      if (b['id'] == creatorId) return 1;
      return 0;
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Group Info',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // =========================
            // 🔵 GROUP HEADER CARD
            // =========================
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _showPhotoOptions(isMember),
                      child: CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 52,
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.white,
                          backgroundImage: _avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: widget.group['avatar_url'] == null
                              ? const Icon(
                                  Icons.group,
                                  color: Color(0xFF171A3F),
                                )
                              : null,
                        ),
                      ),
                    ),

                    // 🔴 REMOVE BUTTON (X)
                    if (widget.group['avatar_url'] != null && isMember)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _removeAvatar,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(6),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                    if (_isUploading) const CircularProgressIndicator(),
                  ],
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        widget.group['name'] ?? 'Unnamed Group',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    const SizedBox(width: 8),

                    if (isMember)
                      GestureDetector(
                        onTap: _showEditModal,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),

                if ((widget.group['description'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.group['description'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // =========================
            // 👥 MEMBERS CARD
            // =========================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kCardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    offset: const Offset(0, 8),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Members',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Builder(
                        builder: (_) {
                          final creator = members.firstWhere(
                            (m) => m['id'] == widget.group['created_by'],
                            orElse: () => {},
                          );

                          if (creator.isEmpty) return const SizedBox();

                          return Text(
                            'Created by ${creator['name']}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (members.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kTileColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No members found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    ...sortedMembers.map((m) => _memberTile(m)),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showEditModal() {
    final nameCtrl = TextEditingController(text: widget.group['name']);
    final descCtrl = TextEditingController(
      text: widget.group['description'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kCardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Group',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              // SAME TILE STYLE
              _dashboardTile(Icons.group, 'Group Name', nameCtrl, true),

              const SizedBox(height: 12),

              _dashboardTile(Icons.description, 'Description', descCtrl, true),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await Supabase.instance.client
                        .from('groups')
                        .update({
                          'name': nameCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                        })
                        .eq('id', widget.group['id']);

                    setState(() {
                      widget.group['name'] = nameCtrl.text.trim();
                      widget.group['description'] = descCtrl.text.trim();
                    });

                    if (ctx.mounted) Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Group updated')),
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEEEEEE),
                    foregroundColor: const Color(0xFF171A3F),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboardTile(
    IconData icon,
    String label,
    TextEditingController controller,
    bool enabled,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kTileColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    final avatarUrl = m['avatar_url'];

    final rawColor = m['color'] ?? '#888888';

    final isCreator = m['id'] == widget.group['created_by'];
    final color = Color(
      int.parse('FF${rawColor.replaceAll('#', '')}', radix: 16),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: kTileColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null
                ? Image.network(avatarUrl, fit: BoxFit.cover)
                : const Icon(Icons.person, color: Color(0xFF171A3F)),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  m['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                if (isCreator) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Group Creator',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploading = true);

    try {
      final groupId = widget.group['id'];

      // Remove from DB
      await Supabase.instance.client
          .from('groups')
          .update({'avatar_url': null})
          .eq('id', groupId);

      setState(() {
        widget.group['avatar_url'] = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group photo removed')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }
}
