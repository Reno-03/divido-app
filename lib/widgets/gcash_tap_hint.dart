import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GcashTapHint extends StatefulWidget {
  const GcashTapHint({super.key});

  @override
  State<GcashTapHint> createState() => GcashTapHintState();
}

class GcashTapHintState extends State<GcashTapHint> {
  static const _prefKey = 'gcash_pill_hint_dismissed';
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

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF007AFF).withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 14,
            color: Color(0xFF007AFF),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Tap the GCash pill to let others know your number is GCash ready!',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _dismiss,
            child: Icon(
              Icons.close,
              size: 13,
              color: const Color(0xFF007AFF).withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
