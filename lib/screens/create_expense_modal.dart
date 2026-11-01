import 'package:divido_app/providers/group_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

class CreateExpenseModal extends StatefulWidget {
  final Future<void> Function(
    String title,
    double total,
    Set<String> payerIds,
    Map<String, double> customAmounts,
    bool isEqualSplit,
    String description,
  )
  onSubmit;

  const CreateExpenseModal({super.key, required this.onSubmit});

  @override
  State<CreateExpenseModal> createState() => _CreateExpenseModalState();
}

class _CreateExpenseModalState extends State<CreateExpenseModal> {
  final _titleController = TextEditingController();
  final _totalController = TextEditingController();
  final _ownerCustomAmount = TextEditingController();
  final _descriptionController = TextEditingController();

  final _selectedUsers = <String>{};
  final _customAmounts = <String, TextEditingController>{};
  bool _isEqualSplit = true;
  bool _isLoading = false;
  bool _isLoadingUsers = true;
  String? _usersError;
  List<Map<String, dynamic>> _users = [];

  final _supabase = Supabase.instance.client;
  final _currentUserId = CurrentUser.instance.id;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final groupProvider = Provider.of<GroupProvider>(context, listen: false);
      final memberIds = groupProvider.members
          .map((m) => m['id'] as String)
          .toList();

      final response = await _supabase
          .from('profiles')
          .select('id, firstname, lastname, color, avatar_url')
          .inFilter('id', memberIds);

      final users = List<Map<String, dynamic>>.from(
        response,
      ).where((u) => u['id'] != _currentUserId).toList();

      if (!mounted) return;
      setState(() {
        _users = users;
        _isLoadingUsers = false;
        for (final user in users) {
          _customAmounts[user['id']] = TextEditingController();
        }
      });
    } catch (error) {
      debugPrint('Create expense member load failed: $error');
      if (!mounted) return;
      setState(() {
        _usersError = 'Could not load group members.';
        _isLoadingUsers = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _totalController.dispose();
    _ownerCustomAmount.dispose();
    _descriptionController.dispose();
    for (final c in _customAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _assignedTotal {
    final payersSum = _selectedUsers.fold<double>(
      0,
      (sum, uid) =>
          sum + (double.tryParse(_customAmounts[uid]?.text ?? '') ?? 0),
    );
    return payersSum + (double.tryParse(_ownerCustomAmount.text) ?? 0);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final total = double.tryParse(_totalController.text) ?? 0;
    final description = _descriptionController.text.trim();

    if (title.isEmpty) {
      _showValidationMessage('Add a title for this expense.');
      return;
    }
    if (total <= 0) {
      _showValidationMessage('Enter an amount greater than zero.');
      return;
    }
    if (_selectedUsers.isEmpty) {
      _showValidationMessage('Select at least one group member.');
      return;
    }

    if (!_isEqualSplit) {
      if ((_assignedTotal - total).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom amounts must add up to the total.'),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    final customAmountValues = {
      for (final uid in _selectedUsers)
        uid: double.tryParse(_customAmounts[uid]?.text ?? '') ?? 0,
    };
    customAmountValues[_currentUserId!] =
        double.tryParse(_ownerCustomAmount.text) ?? 0;

    final payerIds = {..._selectedUsers, _currentUserId};

    try {
      await widget.onSubmit(
        title,
        total,
        payerIds,
        customAmountValues,
        _isEqualSplit,
        description,
      );

      if (mounted) Navigator.pop(context);
    } catch (error) {
      debugPrint('Create expense submission failed: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showValidationMessage('Could not create the expense. Please try again.');
    }
  }

  void _showValidationMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _avatar(Map<String, dynamic> user) {
    final raw = user['color'] as String? ?? '#6366F1';
    final color = Color(int.parse('FF${raw.replaceAll('#', '')}', radix: 16));
    final firstName = user['firstname'] as String? ?? '';
    final lastName = user['lastname'] as String? ?? '';
    final initials =
        '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
            .toUpperCase();
    final avatarUrl = user['avatar_url'] as String?;

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      clipBehavior: Clip.antiAlias,
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 12,
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
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
    );
  }

  InputDecoration _inputDecoration(String label, {String? prefix}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefix,
      prefixStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFB8B9FF), width: 1.5),
      ),
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = double.tryParse(_totalController.text) ?? 0;
    final perPerson = _selectedUsers.isNotEmpty
        ? total / (_selectedUsers.length + 1)
        : 0.0;

    final remaining = total - _assignedTotal;
    final isOver = remaining < -0.01;
    final isExact = remaining.abs() <= 0.01;
    final canSubmit =
        !_isLoading &&
        !_isLoadingUsers &&
        _titleController.text.trim().isNotEmpty &&
        total > 0 &&
        _selectedUsers.isNotEmpty &&
        (_isEqualSplit || isExact);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121532),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
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

            // header
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB8B9FF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFFB8B9FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New expense',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Add the details and split with your group',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // title field
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDecoration('Title'),
              style: const TextStyle(fontSize: 16),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: _inputDecoration('Description (Optional)'),
              style: const TextStyle(fontSize: 16),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),

            // total field
            TextField(
              controller: _totalController,
              textInputAction: TextInputAction.done,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inputDecoration('Total amount', prefix: '₱  ')
                  .copyWith(
                    prefixStyle: const TextStyle(
                      color: Color(0xFFB8B9FF),
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 20),

            const SizedBox(height: 2),

            // split mode
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Split method',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isEqualSplit
                        ? 'Divide the total evenly between everyone.'
                        : 'Set how much each person contributed.',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Equal'),
                        icon: Icon(Icons.balance, size: 16),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Custom'),
                        icon: Icon(Icons.tune, size: 16),
                      ),
                    ],
                    selected: {_isEqualSplit},
                    onSelectionChanged: (val) =>
                        setState(() => _isEqualSplit = val.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.standard,
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                        (states) => states.contains(WidgetState.selected)
                            ? const Color(0xFFB8B9FF).withValues(alpha: 0.18)
                            : Colors.transparent,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith<Color>(
                        (states) => states.contains(WidgetState.selected)
                            ? const Color(0xFFCECEFF)
                            : Colors.white60,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // payers section header
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Who was involved?',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Select everyone sharing this expense.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedUsers.length + 1} selected',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_isEqualSplit && _selectedUsers.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB8B9FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: const Color(0xFFB8B9FF).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      '₱${perPerson.toStringAsFixed(2)} per person',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFCECEFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),

            const SizedBox(height: 10),

            // owner custom amount
            if (!_isEqualSplit) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    // current user avatar
                    () {
                      final raw = CurrentUser.instance.color ?? '#6366F1';
                      final color = Color(
                        int.parse('FF${raw.replaceAll('#', '')}', radix: 16),
                      );
                      final initials =
                          '${CurrentUser.instance.firstname?[0].toUpperCase() ?? ''}${CurrentUser.instance.lastname?[0].toUpperCase() ?? ''}';
                      final avatarUrl = CurrentUser.instance.avatarUrl;
                      return Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: avatarUrl != null && avatarUrl.isNotEmpty
                            ? Image.network(
                                avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      fontSize: 12,
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                      );
                    }(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${CurrentUser.instance.firstname ?? ''} (you)',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _ownerCustomAmount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          prefixText: '₱ ',
                          prefixStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          hintText: '0.00',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.blue,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // user list
            if (_isLoadingUsers)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_usersError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _usersError!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLoadingUsers = true;
                          _usersError = null;
                        });
                        _loadUsers();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_users.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.group_add_outlined,
                      color: Colors.white54,
                      size: 26,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No other members yet',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Invite someone to your group to split an expense.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              ..._users.map((user) {
                final name =
                    '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}'
                        .trim();
                final uid = user['id'] as String;
                final isSelected = _selectedUsers.contains(uid);

                return Column(
                  children: [
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedUsers.remove(uid);
                              _customAmounts[uid]?.clear();
                            } else {
                              _selectedUsers.add(uid);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(
                                    0xFFB8B9FF,
                                  ).withValues(alpha: 0.09)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(
                                      0xFFB8B9FF,
                                    ).withValues(alpha: 0.3)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              _avatar(user),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (!_isEqualSplit && isSelected)
                                SizedBox(
                                  width: 100,
                                  child: TextField(
                                    controller: _customAmounts[uid],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    textAlign: TextAlign.right,
                                    decoration: InputDecoration(
                                      prefixText: '₱ ',
                                      prefixStyle: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      hintText: '0.00',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.15,
                                          ),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: Colors.blue,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                )
                              else
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    key: ValueKey(isSelected),
                                    size: 22,
                                    color: isSelected
                                        ? const Color(0xFFB8B9FF)
                                        : Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),

            // remaining indicator
            if (!_isEqualSplit && _selectedUsers.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isExact
                      ? Colors.green.withValues(alpha: 0.1)
                      : isOver
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isExact
                        ? Colors.green.withValues(alpha: 0.3)
                        : isOver
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExact
                          ? Icons.check_circle_outline
                          : isOver
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 16,
                      color: isExact
                          ? Colors.green.shade400
                          : isOver
                          ? Colors.red.shade400
                          : Colors.white54,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isExact
                          ? 'Amounts match total'
                          : isOver
                          ? 'Over by ₱${remaining.abs().toStringAsFixed(2)}'
                          : 'Remaining: ₱${remaining.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isExact
                            ? Colors.green.shade400
                            : isOver
                            ? Colors.red.shade400
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF171A3F),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                  disabledForegroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(vertical: 21),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF171A3F),
                        ),
                      )
                    : const Icon(Icons.add_rounded, size: 23),
                label: Text(
                  _isLoading ? 'Creating expense…' : 'Create expense',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
