import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/current_user.dart';

class GroupProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;
  List<Map<String, dynamic>> _members = [];

  bool _isLoading = false;

  List<Map<String, dynamic>> get groups => _groups;
  Map<String, dynamic>? get selectedGroup => _selectedGroup;
  List<Map<String, dynamic>> get members => _members;
  bool get isLoading => _isLoading;

  String? get selectedGroupId => _selectedGroup?['id'] as String?;
  String? get selectedGroupName => _selectedGroup?['name'] as String?;

  List<Map<String, dynamic>> groupMembers = [];

  Future<void> fetchGroupMembers(String groupId) async {
    final data = await Supabase.instance.client
        .from('group_members')
        .select('user_id, profiles(*)')
        .eq('group_id', groupId);

    groupMembers = data.map((e) {
      final user = e['profiles'];

      return {
        'id': user['id'], // IMPORTANT
        'name': '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}'.trim(),
        'avatar_url': user['avatar_url'],
        'color': user['color'],
      };
    }).toList();

    notifyListeners();
  }

  // ── fetch all groups the current user belongs to ──────────────
  Future<void> fetchGroups() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = CurrentUser.instance.id!;

      final response = await _supabase
          .from('group_members')
          .select(
            'group_id, groups(id, name, description, invite_code, created_by, created_at, avatar_url)',
          )
          .eq('user_id', userId);

      _groups = response
          .map((e) => e['groups'] as Map<String, dynamic>)
          .toList();

      // sort by created_at ascending (oldest first)
      _groups.sort((a, b) {
        final aDate = DateTime.parse(a['created_at'] as String);
        final bDate = DateTime.parse(b['created_at'] as String);
        return aDate.compareTo(bDate); // oldest first
      });

      // auto-select first group if none selected
      final currentSelectedId = _selectedGroup?['id'];

      if (_groups.isEmpty) {
        _selectedGroup = null;
        _members = [];
      } else {
        // if selected group was deleted OR null → auto select first
        final stillExists = _groups.any((g) => g['id'] == currentSelectedId);

        if (currentSelectedId == null || !stillExists) {
          _selectedGroup = _groups.first;
          await _fetchMembers(_groups.first['id']);
        }
      }
    } catch (e) {
      debugPrint('fetchGroups error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ── select a group and fetch its members ──────────────────────
  Future<void> selectGroup(String groupId) async {
    _selectedGroup = _groups.firstWhere((g) => g['id'] == groupId);
    await _fetchMembers(groupId);
    notifyListeners();
  }

  Future<void> _fetchMembers(String groupId) async {
    final response = await _supabase
        .from('group_members')
        .select(
          'user_id, profiles(id, firstname, lastname, color, avatar_url, contact_number, is_gcash_ready)',
        )
        .eq('group_id', groupId);

    _members = response
        .map((e) => e['profiles'] as Map<String, dynamic>)
        .toList();
  }

  // ── create a new group ────────────────────────────────────────
  Future<void> createGroup(String name, {String? description}) async {
    final userId = CurrentUser.instance.id!;

    final group = await _supabase
        .from('groups')
        .insert({
          'name': name,
          'description': description,
          'created_by': userId,
        })
        .select()
        .single();

    // auto-add creator as member
    await _supabase.from('group_members').insert({
      'group_id': group['id'],
      'user_id': userId,
    });

    await fetchGroups();
    await selectGroup(group['id'] as String);
  }

  // ── join a group via invite code ──────────────────────────────
  Future<String?> joinGroup(String inviteCode) async {
    final userId = CurrentUser.instance.id!;

    // find group by invite code
    final group = await _supabase
        .from('groups')
        .select('id, name')
        .eq('invite_code', inviteCode.trim().toUpperCase())
        .maybeSingle();

    if (group == null) return 'Invalid invite code.';

    // check if already a member
    final existing = await _supabase
        .from('group_members')
        .select('id')
        .eq('group_id', group['id'])
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return 'You are already in this group.';

    // join
    await _supabase.from('group_members').insert({
      'group_id': group['id'],
      'user_id': userId,
    });

    await fetchGroups();
    await selectGroup(group['id'] as String);

    return null; // null = success
  }

  // ── leave a group ─────────────────────────────────────────────
  Future<void> leaveGroup(String groupId) async {
    final userId = CurrentUser.instance.id!;

    await _supabase
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);

    _groups.removeWhere((g) => g['id'] == groupId);

    if (_selectedGroup?['id'] == groupId) {
      _selectedGroup = null;
      _members = [];
      if (_groups.isNotEmpty) {
        await selectGroup(_groups.first['id'] as String);
      }
    }

    notifyListeners();
  }

  // ── clear (on logout) ─────────────────────────────────────────
  void clear() {
    _groups = [];
    _selectedGroup = null;
    _members = [];
    _isLoading = false;
    notifyListeners();
  }
}
