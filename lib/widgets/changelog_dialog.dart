import 'package:flutter/material.dart';
import '../services/changelog_service.dart';

class ChangelogDialog extends StatefulWidget {
  const ChangelogDialog({super.key});

  @override
  State<ChangelogDialog> createState() => _ChangelogDialogState();
}

class _ChangelogDialogState extends State<ChangelogDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final contentHeight = MediaQuery.sizeOf(context).height * 0.55;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: const Color(0xFF171A3F),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Row(
        children: [
          const Icon(
            Icons.new_releases_outlined,
            color: Color(0xFF8FE3B0),
            size: 24,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "What's new in Divido",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
              maxLines: 2,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: contentHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'VERSION 1.3.0',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'A clearer view of shared expenses, with a smoother way to keep everything moving.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                _highlight(
                  Icons.account_balance_wallet_outlined,
                  'See who owes whom',
                  'Balances are clearer, with an indicator when anything is still unsettled.',
                ),
                _divider(),
                _highlight(
                  Icons.done_all_rounded,
                  'Collect with fewer taps',
                  'Mark your expenses as paid together from My Expenses.',
                ),
                _divider(),
                _highlight(
                  Icons.dashboard_outlined,
                  'A more helpful dashboard',
                  'Get a greeting and quick action based on your current balances.',
                ),
                _divider(),
                _highlight(
                  Icons.bar_chart_rounded,
                  'Track spending over time',
                  'Compare your share with group spending by day, week, or month.',
                ),
                _divider(),
                _highlight(
                  Icons.bolt_outlined,
                  'Smoother everyday use',
                  'Expense lists, avatars, group details, and navigation feel more polished.',
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  value: _dontShowAgain,
                  onChanged: (value) =>
                      setState(() => _dontShowAgain = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    "Don't show again",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  activeColor: const Color(0xFF8FE3B0),
                  checkColor: const Color(0xFF171A3F),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              if (_dontShowAgain) await ChangelogService.markSeen();
              if (context.mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF171A3F),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _highlight(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF8FE3B0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
    height: 1,
    color: Colors.white.withValues(alpha: 0.1),
  );
}
