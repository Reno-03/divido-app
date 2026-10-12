import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

import '../providers/group_provider.dart';
import '../widgets/dashboard_ui.dart';

Future<T?> showDashSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    backgroundColor: kDashNavy,
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

class _ConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String? boldName;
  final String confirmText;
  final Color confirmColor;

  const _ConfirmSheet({
    required this.title,
    required this.message,
    this.boldName,
    required this.confirmText,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Colors.white70),
            children: [
              TextSpan(text: message),
              if (boldName != null)
                TextSpan(
                  text: boldName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, false),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: confirmColor.withValues(alpha: 0.15),
                  foregroundColor: confirmColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  confirmText,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeleteGroupSheet extends StatefulWidget {
  final String groupName;
  final String groupId;

  const _DeleteGroupSheet({required this.groupName, required this.groupId});

  @override
  State<_DeleteGroupSheet> createState() => _DeleteGroupSheetState();
}

class _DeleteGroupSheetState extends State<_DeleteGroupSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isDeleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expected = "sudo remove ${widget.groupName}";
    final matches = _controller.text.trim() == expected;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Type the sudo command to confirm deletion:',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: expected,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.blue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (!matches || _isDeleting)
                ? null
                : () async {
                    setState(() => _isDeleting = true);
                    final groupProvider = context.read<GroupProvider>();
                    final messenger = ScaffoldMessenger.of(context);

                    try {
                      await Supabase.instance.client
                          .from('groups')
                          .delete()
                          .eq('id', widget.groupId);

                      await groupProvider.fetchGroups();

                      if (!context.mounted) return;
                      Navigator.pop(context, true);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Group deleted')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Delete failed: $e')),
                      );
                      setState(() => _isDeleting = false);
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
            child: _isDeleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Confirm Delete',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }
}

class _EditGroupSheet extends StatefulWidget {
  final String initialName;
  final String initialDescription;
  final String groupId;
  final Function(String name, String description) onSaved;

  const _EditGroupSheet({
    required this.initialName,
    required this.initialDescription,
    required this.groupId,
    required this.onSaved,
  });

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _descCtrl = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameCtrl,
          maxLength: 40,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Group Name',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.blue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descCtrl,
          maxLength: 120,
          maxLines: 2,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Description',
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: Colors.blue, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _isSaving
                ? null
                : () async {
                    final nameText = _nameCtrl.text.trim();
                    if (nameText.isEmpty) return;

                    setState(() => _isSaving = true);
                    final messenger = ScaffoldMessenger.of(context);
                    final groupProvider = context.read<GroupProvider>();

                    try {
                      await Supabase.instance.client
                          .from('groups')
                          .update({
                            'name': nameText,
                            'description': _descCtrl.text.trim(),
                          })
                          .eq('id', widget.groupId);

                      await groupProvider.fetchGroups();

                      widget.onSaved(nameText, _descCtrl.text.trim());

                      if (!context.mounted) return;
                      Navigator.pop(context);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Group updated')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Update failed: $e')),
                      );
                      setState(() => _isSaving = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEEEEEE),
              foregroundColor: const Color(0xFF171A3F),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF171A3F),
                    ),
                  )
                : const Text(
                    'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PhotoSheet extends StatelessWidget {
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _PhotoSheet({required this.onPick, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pop(context);
            onPick();
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.photo_library_outlined, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Upload / Change Photo',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onRemove!();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text(
                    'Remove photo',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool isMember;
  final bool isUploading;
  final int? avatarVersion;
  final VoidCallback onPhotoTap;
  final VoidCallback onEditTap;

  const _GroupHeader({
    required this.group,
    required this.isMember,
    required this.isUploading,
    required this.avatarVersion,
    required this.onPhotoTap,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final rawUrl = group['avatar_url'];
    final avatarUrl = (rawUrl != null && avatarVersion != null)
        ? '$rawUrl?v=$avatarVersion'
        : rawUrl;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: isMember ? onPhotoTap : null,
              child: DashAvatar(
                url: avatarUrl,
                size: 96,
              ),
            ),
            if (isMember && !isUploading)
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onPhotoTap,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: kDashNavy,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            if (isUploading)
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                group['name'] ?? 'Unnamed Group',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMember) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEditTap,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kDashGlass,
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
          ],
        ),
        if ((group['description'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            group['description'],
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _MembersSection extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> sortedMembers;
  final String? creatorName;

  const _MembersSection({
    required this.isLoading,
    required this.sortedMembers,
    required this.creatorName,
  });

  @override
  Widget build(BuildContext context) {
    return DashSection(
      title: 'Members',
      subtitle: !isLoading && creatorName != null
          ? 'Created by $creatorName'
          : null,
      child: isLoading
          ? Column(
              children: List.generate(
                3,
                (index) => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: DashSkeleton(height: 56, radius: 12),
                ),
              ),
            )
          : sortedMembers.isEmpty
              ? const DashEmpty('No members found.')
              : Column(
                  children: sortedMembers.map((m) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DashMemberRow(
                        name: m['name'] ?? 'Unknown',
                        avatarUrl: m['avatar_url'],
                        colorHex: m['color'] ?? '#888888',
                        isCreator: m['isCreator'] == true,
                      ),
                    );
                  }).toList(),
                ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white54,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  final VoidCallback onDeleteGroup;
  final VoidCallback onRemoveMember;

  const _DangerZone({
    required this.onDeleteGroup,
    required this.onRemoveMember,
  });

  @override
  Widget build(BuildContext context) {
    return DashSection(
      title: 'Danger zone',
      subtitle: 'Only group creators can perform these actions.',
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.person_remove_rounded,
            color: Colors.orangeAccent,
            title: 'Remove member',
            subtitle: 'Kick a member from this group',
            onTap: onRemoveMember,
          ),
          const SizedBox(height: 8),
          _ActionRow(
            icon: Icons.delete_forever_rounded,
            color: Colors.redAccent,
            title: 'Delete group',
            subtitle: 'Permanently remove this group and all data',
            onTap: onDeleteGroup,
          ),
        ],
      ),
    );
  }
}

class _LeaveSection extends StatelessWidget {
  final VoidCallback onLeaveGroup;

  const _LeaveSection({required this.onLeaveGroup});

  @override
  Widget build(BuildContext context) {
    return DashSection(
      title: 'Leave group',
      child: _ActionRow(
        icon: Icons.logout_rounded,
        color: Colors.redAccent,
        title: 'Leave group',
        subtitle: 'You will need an invite code to rejoin.',
        onTap: onLeaveGroup,
      ),
    );
  }
}

class GroupInfoPage extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupInfoPage({super.key, required this.group});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  bool _isUploading = false;
  bool _membersLoading = true;
  int? _avatarVersion;

  List<Map<String, dynamic>> _membersSource = [];
  List<Map<String, dynamic>> _sortedMembers = [];
  bool _isMember = false;
  bool _isCreator = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMembers();
    });
  }

  Future<void> _loadMembers() async {
    setState(() => _membersLoading = true);
    try {
      await context.read<GroupProvider>().fetchGroupMembers(widget.group['id']);
    } finally {
      if (mounted) {
        setState(() => _membersLoading = false);
      }
    }
  }

  void _cacheGroupView(List<Map<String, dynamic>> members) {
    if (identical(_membersSource, members)) return;
    _membersSource = members;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _isCreator = currentUserId == widget.group['created_by'];
    _isMember = members.any((m) => m['id'] == currentUserId);

    final creatorId = widget.group['created_by'];
    final cloned = members.map((m) {
      final isCreatorMember = m['id'] == creatorId;
      return {...m, 'isCreator': isCreatorMember};
    }).toList();

    cloned.sort((a, b) {
      if (a['id'] == creatorId) return -1;
      if (b['id'] == creatorId) return 1;
      return 0;
    });

    _sortedMembers = cloned;
  }

  Future<void> _uploadBytes(Uint8List bytes, String? mimeType) async {
    if (_isUploading) return;
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

      await Supabase.instance.client
          .from('groups')
          .update({'avatar_url': rawUrl})
          .eq('id', groupId);

      await groupProvider.fetchGroups();

      if (!mounted) return;
      setState(() {
        widget.group['avatar_url'] = rawUrl;
        _avatarVersion = DateTime.now().millisecondsSinceEpoch;
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
    if (_isUploading) return;
    if (kIsWeb) {
      final input = web.HTMLInputElement()
        ..type = 'file'
        ..accept = 'image/*';

      input.click();
      await input.onChange.first;

      final file = input.files?.item(0);
      if (file == null) return;

      if (file.size > 5 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File size exceeds 5 MB limit')),
        );
        return;
      }

      final buffer = await file.arrayBuffer().toDart;
      final bytes = Uint8List.view(buffer.toDart);

      await _uploadBytes(bytes, file.type);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    await _uploadBytes(bytes, null);
  }

  Future<void> _removeAvatar() async {
    if (_isUploading) return;
    setState(() => _isUploading = true);
    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final groupId = widget.group['id'];

      await Supabase.instance.client
          .from('groups')
          .update({'avatar_url': null})
          .eq('id', groupId);

      await groupProvider.fetchGroups();

      if (!mounted) return;
      setState(() {
        widget.group['avatar_url'] = null;
        _avatarVersion = DateTime.now().millisecondsSinceEpoch;
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

  void _showPhotoOptions() {
    showDashSheet(
      context,
      title: 'Group Photo',
      child: _PhotoSheet(
        onPick: _pickImage,
        onRemove: widget.group['avatar_url'] != null ? _removeAvatar : null,
      ),
    );
  }

  void _showEditModal() {
    showDashSheet(
      context,
      title: 'Edit Group',
      child: _EditGroupSheet(
        initialName: widget.group['name'] ?? '',
        initialDescription: widget.group['description'] ?? '',
        groupId: widget.group['id'],
        onSaved: (newName, newDesc) {
          setState(() {
            widget.group['name'] = newName;
            widget.group['description'] = newDesc;
          });
        },
      ),
    );
  }

  void _showDeleteGroupPrompt() {
    showDashSheet(
      context,
      title: 'Delete Group',
      child: _DeleteGroupSheet(
        groupName: widget.group['name'] ?? 'Group',
        groupId: widget.group['id'],
      ),
    );
  }

  void _showRemoveMemberSheet() {
    final provider = context.read<GroupProvider>();
    final groupId = widget.group['id'];
    final removableMembers = provider.groupMembers
        .where((m) => m['id'] != widget.group['created_by'])
        .toList();

    showDashSheet(
      context,
      title: 'Remove Member',
      child: removableMembers.isEmpty
          ? const Text(
              'No removable members',
              style: TextStyle(color: Colors.white70),
            )
          : Column(
              children: removableMembers.map((m) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: DashAvatar(
                    url: m['avatar_url'],
                    size: 40,
                  ),
                  title: Text(
                    m['name'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.redAccent,
                  ),
                  onTap: () async {
                    final confirmed = await showDashSheet<bool>(
                      context,
                      title: 'Remove Member',
                      child: _ConfirmSheet(
                        title: 'Remove Member',
                        message: 'Are you sure you want to remove ',
                        boldName: m['name'] ?? 'this member',
                        confirmText: 'Remove',
                        confirmColor: Colors.redAccent,
                      ),
                    );

                    if (confirmed != true) return;
                    if (!mounted) return;
                    final messenger = ScaffoldMessenger.of(context);

                    try {
                      await provider.removeMember(
                        groupId: groupId,
                        userId: m['id'],
                      );

                      if (!mounted) return;
                      Navigator.pop(context); // close remove member sheet
                      messenger.showSnackBar(
                        SnackBar(content: Text('${m['name'] ?? 'Member'} removed')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to remove member: $e')),
                      );
                    }
                  },
                );
              }).toList(),
            ),
    );
  }

  void _showLeavePrompt() async {
    final confirmed = await showDashSheet<bool>(
      context,
      title: 'Leave Group',
      child: _ConfirmSheet(
        title: 'Leave Group',
        message: 'Are you sure you want to leave ',
        boldName: widget.group['name'] ?? 'this group',
        confirmText: 'Leave',
        confirmColor: Colors.redAccent,
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final groupProvider = context.read<GroupProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await groupProvider.leaveGroup(widget.group['id'] as String);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Left ${widget.group['name'] ?? 'group'}')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to leave group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = context.select<GroupProvider, List<Map<String, dynamic>>>(
      (p) => p.groupMembers,
    );

    _cacheGroupView(members);

    final creatorMember = members.firstWhere(
      (m) => m['id'] == widget.group['created_by'],
      orElse: () => {},
    );
    final creatorName = creatorMember['name'];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Group Info',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.of(context).padding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  _GroupHeader(
                    group: widget.group,
                    isMember: _isMember && !_membersLoading,
                    isUploading: _isUploading,
                    avatarVersion: _avatarVersion,
                    onPhotoTap: _showPhotoOptions,
                    onEditTap: _showEditModal,
                  ),
                  if (!_membersLoading && widget.group['invite_code'] != null && _isMember) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.group['invite_code']),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Invite code copied to clipboard'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: kDashGlass,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Invite code  ${widget.group['invite_code']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (!_membersLoading) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${members.length} members${creatorName != null ? ' · Created by $creatorName' : ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _MembersSection(
                    isLoading: _membersLoading,
                    sortedMembers: _sortedMembers,
                    creatorName: creatorName,
                  ),
                  if (!_membersLoading && _isCreator) ...[
                    const SizedBox(height: 24),
                    _DangerZone(
                      onDeleteGroup: _showDeleteGroupPrompt,
                      onRemoveMember: _showRemoveMemberSheet,
                    ),
                  ],
                  if (!_membersLoading && _isMember && !_isCreator) ...[
                    const SizedBox(height: 24),
                    _LeaveSection(onLeaveGroup: _showLeavePrompt),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}