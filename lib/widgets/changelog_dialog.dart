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
      backgroundColor: Color(0xFF171A3F),
      title: Row(
        children: [
          Icon(Icons.new_releases_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          const Text(
            "What's New",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              'v0.5.0-beta — Nudge You',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),

          _section('✨ New', [
            'Add Payment with Cash or GCash via segmented button',
            'Upload and edit your circle avatar photo on Profile page',
            'Nudge feature — poke people who owe you (replaces Settle button)',
          ]),
          const SizedBox(height: 10),
          _section('🔧 Optimized', [
            'Balance page header now properly aligns avatar and status bubble',
            'Shimmer skeletal loading on All, Mine, and Balance pages',
            'Improved Payment dialog UI/UX',
            'Balance cards sorted by most nudged first, then by amount owed',
            'Avatar photo with initials fallback across All, Mine, Balance, Profile, and sidebar',
            'Better UX for editing and removing avatar photo on web and mobile PWA',
            'Avatar upload step added after registration',
          ]),
          const SizedBox(height: 10),
          _section('🗑️ Removed', ['Email confirmation temporarily disabled']),

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
          ),
          child: const Text('Got it!'),
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
