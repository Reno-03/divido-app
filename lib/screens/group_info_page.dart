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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GroupProvider>().fetchGroupMembers(widget.group['id']);
    });

    final url = widget.group['avatar_url'];

    if (url != null) {
      _avatarUrl = '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  // Future<void> _fetchGroup() async {
  //   final groupId = widget.group['id'];

  //   final data = await Supabase.instance.client
  //       .from('groups')
  //       .select()
  //       .eq('id', groupId)
  //       .single();

  //   setState(() {
  //     widget.group['avatar_url'] = data['avatar_url'];
  //     _avatarUrl = data['avatar_url'] != null
  //         ? '${data['avatar_url']}?v=${DateTime.now().millisecondsSinceEpoch}'
  //         : null;
  //   });
  // }

  // =========================
  // 📸 IMAGE UPLOAD
  // =========================
  Future<void> _uploadBytes(Uint8List bytes, String? mimeType) async {
    setState(() => _isUploading = true);
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);

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

      // final url = '$rawUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client
          .from('groups')
          .update({'avatar_url': rawUrl})
          .eq('id', groupId);

      await groupProvider.fetchGroups();

      if (!mounted) return;
      setState(() {
        widget.group['avatar_url'] = rawUrl;
        _avatarUrl = '$rawUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Group photo updated')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
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
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Group Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupProvider>();
    final members = provider.groupMembers;

    final currentUserId = Supabase.instance.client.auth.currentUser!.id;

    final isCreator = currentUserId == widget.group['created_by'];

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

            const SizedBox(height: 16),

            if (isCreator)
              Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3C63),
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
                    const Text(
                      'Danger Zone',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'Only group creators can perform these actions.',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),

                    const SizedBox(height: 16),

                    // DELETE GROUP TILE
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showDeleteGroupPrompt,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171A3F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_forever,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(width: 12),

                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Delete Group',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Permanently remove this group and all data',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showRemoveMemberSheet,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171A3F),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.person_remove,
                                color: Colors.orangeAccent,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Remove Member',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Kick a member from this group',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showRemoveMemberSheet() {
    final provider = context.read<GroupProvider>();
    final groupId = widget.group['id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      backgroundColor: const Color(0xFF171A3F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final members = provider.groupMembers
            .where((m) => m['id'] != widget.group['created_by'])
            .toList();

        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: members.isEmpty
              ? const Text(
                  "No removable members",
                  style: TextStyle(color: Colors.white70),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // drag handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Remove Member',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
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
                    const SizedBox(height: 16),

                    ...members.map((m) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: m['avatar_url'] != null
                              ? NetworkImage(m['avatar_url'])
                              : null,
                          child: m['avatar_url'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(m['name']),
                        trailing: const Icon(
                          Icons.remove_circle,
                          color: Colors.redAccent,
                        ),
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF171A3F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text(
                                'Remove Member',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: Text(
                                'Are you sure you want to remove ${m['name']} from this group?',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;
                          if (!mounted) return;
                          final messenger = ScaffoldMessenger.of(context);

                          await provider.removeMember(
                            groupId: groupId,
                            userId: m['id'],
                          );

                        if (!mounted) return;
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                            SnackBar(content: Text('${m['name']} removed')),
                          );
                        },
                      );
                    }),
                  ],
                ),
        );
      },
    );
  }

  void _showDeleteGroupPrompt() {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delete Group',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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

            const Text(
              'Type the sudo command to confirm deletion:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: "sudo remove ${widget.group['name']}",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final groupProvider = context.read<GroupProvider>();
                  final messenger = ScaffoldMessenger.of(context);
                  final input = controller.text.trim();
                  final expected = "sudo remove ${widget.group['name']}";

                  if (input != expected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Command does not match')),
                    );
                    return;
                  }

                  try {
                    await Supabase.instance.client
                        .from('groups')
                        .delete()
                        .eq('id', widget.group['id']);

                    await groupProvider.fetchGroups();

                    if (!mounted) return;
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) Navigator.pop(context); // exit page

                    messenger.showSnackBar(
                      const SnackBar(content: Text('Group deleted')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text('Delete failed: $e')),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Confirm Delete',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
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
      barrierColor: Colors.black.withValues(alpha: 0.85),
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
          // we can remove the inner card decoration since the bottom sheet is styled already
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Group',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                    final messenger = ScaffoldMessenger.of(context);
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

                    if (!mounted) return;
                    if (ctx.mounted) Navigator.pop(ctx);

                    messenger.showSnackBar(
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
    final messenger = ScaffoldMessenger.of(context);

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

      messenger.showSnackBar(
        const SnackBar(content: Text('Group photo removed')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}
