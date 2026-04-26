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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFF171A3F),
      title: Row(
        children: [
          const Icon(Icons.new_releases_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          const Text(
            "What's New",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Text(
                'v1.0.0 — Initial Stable Release 🎉',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 14),

            _section('🆕 New', [
              'Terms and Conditions screen before account creation',
              'Balance pill on Groups page — see who you owe at a glance',
              'Invite Code now visible directly on the Group Info page',
              'Fallback empty states for Balances, All, and Mine pages',
              'RLS Policies added in Supabase for secure database access',
              'Home App Bar has now Group Photo Avatar',
            ]),

            const SizedBox(height: 10),

            _section('⚡ Optimized & Fixed', [
              'Dashboard metrics now update correctly when switching groups quickly',
              'Fixed Hero tag conflict exception in home.dart',
              'Set Status modal on Profile page redesigned',
              'Circle avatar fixed on Balance Activity page',
              'All bottom modal sheets updated to match Divido theme',
              'Create Expense no longer infinite-loads when group has 1 member',
              'Breathing Divido logo now uses Flutter animations instead of GIF',
              'Improved and polished UI/UX across all screens',
            ]),

            const SizedBox(height: 16),

            // Don't show again checkbox
            GestureDetector(
              onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _dontShowAgain,
                      onChanged: (v) =>
                          setState(() => _dontShowAgain = v ?? false),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Don't show again",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            if (_dontShowAgain) await ChangelogService.markSeen();
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF171A3F),
          ),
          child: const Text(
            'Got it!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}