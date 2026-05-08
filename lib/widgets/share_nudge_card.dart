import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareNudgeCard extends StatefulWidget {
  const ShareNudgeCard({super.key});

  @override
  State<ShareNudgeCard> createState() => _ShareNudgeCardState();
}

class _ShareNudgeCardState extends State<ShareNudgeCard> {
  static const _prefKey = 'share_nudge_dismissed';
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _dismissed = prefs.getBool(_prefKey) ?? false);
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    if (mounted) setState(() => _dismissed = true);
  }

  Future<void> _share() async {
    if (kIsWeb) {
      await Clipboard.setData(
        const ClipboardData(
          text:
            'Split bills effortlessly with Divido!\n\n'
            'Track shared expenses, settle debts, and stop doing the math — '
            'Divido handles it all.\n\n'
            '👉 Try it here: https://divido-app.vercel.app',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copied. Paste it anywhere!')),
        );
      }
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        text:
            'Split bills effortlessly with Divido!\n\n'
            'Track shared expenses, settle debts, and stop doing the math — '
            'Divido handles it all.\n\n'
            '👉 Try it here: https://divido-app.vercel.app',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.25),
            const Color(0xFF1C3C35).withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.share_outlined,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enjoying Divido?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Share it with friends who split bills too.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _share,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Share',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _dismiss,
            child: Icon(
              Icons.close,
              size: 16,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
