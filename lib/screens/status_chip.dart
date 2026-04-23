import 'package:flutter/material.dart';

class StatusChip extends StatefulWidget {
  final String text;
  final TextEditingController controller;

  const StatusChip({
    super.key,
    required this.text,
    required this.controller,
  });

  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip> {
  bool _pressed = false;

  void _applyText() {
    widget.controller.text = widget.text;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        _applyText();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: _pressed ? 0.93 : 1.0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _pressed ? 0.75 : 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(right: 0, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Text(
              widget.text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}