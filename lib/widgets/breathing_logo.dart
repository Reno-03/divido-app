import 'package:flutter/material.dart';

class BreathingLogo extends StatefulWidget {
  const BreathingLogo({super.key});

  @override
  State<BreathingLogo> createState() => BreathingLogoState();
}


class BreathingLogoState extends State<BreathingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
      child: Image.asset(
        'assets/divido_logo_only.png', // your static PNG
        height: 100,
      ),
    );
  }
}
