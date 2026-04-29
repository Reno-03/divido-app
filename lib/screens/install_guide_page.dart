import 'package:flutter/material.dart';

class InstallGuidePage extends StatelessWidget {
  const InstallGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Install Divido',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Hero blurb
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3C3C63),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/divido_logo.png',
                          width: 56,
                          height: 56,
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Get the full app experience',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Install Divido on your device for faster access and a native feel.',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Android section
                  _PlatformSection(
                    icon: Icons.phone_android,
                    platformName: 'Android',
                    browserName: 'Chrome',
                    accentColor: const Color(0xFF34A853),
                    steps: const [
                      _StepData(
                        stepNumber: 1,
                        description: 'Open Divido in Chrome\nand tap the ⋮ menu',
                        imagePath: 'assets/install/android_step1.png',
                      ),
                      _StepData(
                        stepNumber: 2,
                        description: 'Select "Add to Home screen"',
                        imagePath: 'assets/install/android_step2.png',
                      ),
                      _StepData(
                        stepNumber: 3,
                        description: 'Tap "Install" to confirm installation',
                        imagePath: 'assets/install/android_step3.png',
                      ),
                      _StepData(
                        stepNumber: 4,
                        description: 'Done installing and ready to use!',
                        imagePath: 'assets/install/android_step4.png',
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // iOS section
                  _PlatformSection(
                    icon: Icons.apple,
                    platformName: 'iPhone / iPad',
                    browserName: 'Safari',
                    accentColor: const Color(0xFF007AFF),
                    steps: const [
                      _StepData(
                        stepNumber: 1,
                        description: 'Open Divido in Safari, press the Share icon',
                        imagePath: 'assets/install/ios_step1.png',
                      ),
                      _StepData(
                        stepNumber: 2,
                        description: 'Tap "Add to Home Screen"',
                        imagePath: 'assets/install/ios_step2.png',
                      ),
                      _StepData(
                        stepNumber: 3,
                        description: 'Tap "Add" in the top right corner',
                        imagePath: 'assets/install/ios_step3.png',
                      ),
                      _StepData(
                        stepNumber: 4,
                        description: 'You\'re all set for Divido on iOS!',
                        imagePath: 'assets/install/ios_step4.png',
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Desktop Chrome section
                  _PlatformSection(
                    icon: Icons.desktop_windows_outlined,
                    platformName: 'Desktop',
                    browserName: 'Chrome',
                    accentColor: const Color(0xFF6366F1),
                    steps: const [
                      _StepData(
                        stepNumber: 1,
                        description: 'Open Divido in Chrome or any browser',
                         imagePath: 'assets/install/desktop_step1.png',
                      ),
                      _StepData(
                        stepNumber: 2,
                        description: 'Click the install icon in the address bar',
                        imagePath: 'assets/install/desktop_step2.png',
                      ),
                      _StepData(
                        stepNumber: 3,
                        description: 'Click "Install" in the prompt',
                        imagePath: 'assets/install/desktop_step3.png',
                      ),
                      _StepData(
                        stepNumber: 4,
                        description: 'Divido opens as a standalone app!',
                        imagePath: 'assets/install/desktop_step4.png',
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Footer note
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No app store needed. Divido installs directly from your browser.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.45),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

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

class _StepData {
  final int stepNumber;
  final String description;
  final String imagePath;

  const _StepData({
    required this.stepNumber,
    required this.description,
    required this.imagePath,
  });
}

// ─────────────────────────────────────────
// Platform section widget
// ─────────────────────────────────────────

class _PlatformSection extends StatelessWidget {
  final IconData icon;
  final String platformName;
  final String browserName;
  final Color accentColor;
  final List<_StepData> steps;

  const _PlatformSection({
    required this.icon,
    required this.platformName,
    required this.browserName,
    required this.accentColor,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Platform header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platformName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'via $browserName',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Steps row
        SizedBox(
          height: 300,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: steps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _StepCard(step: steps[index], accentColor: accentColor);
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Step card widget
// ─────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final _StepData step;
  final Color accentColor;

  const _StepCard({required this.step, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF1F214F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          // Illustration area
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: Image.asset(
                step.imagePath, // e.g. 'assets/install/android_step1.png'
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Label area
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${step.stepNumber}',
                  style: TextStyle(
                    fontSize: 10,
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
