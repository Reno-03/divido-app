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
                        description: 'Tap "Add install" to confirm',
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

// ─────────────────────────────────────────
// Data model
// ─────────────────────────────────────────

enum _IllustrationType {
  androidBrowser,
  androidMenu,
  androidAddToHome,
  iosBrowser,
  iosShare,
  iosAddToHome,
  desktopBrowser,
  desktopInstallIcon,
  desktopPrompt,
  done,
}

class _StepData {
  final int stepNumber;
  final String description;
  final String imagePath;
  final bool isDone;

  const _StepData({
    required this.stepNumber,
    required this.description,
    required this.imagePath,
    this.isDone = false,
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
            separatorBuilder: (_, __) => const SizedBox(width: 12),
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
                  step.isDone ? 'Done' : 'Step ${step.stepNumber}',
                  style: TextStyle(
                    fontSize: 10,
                    color: step.isDone ? Colors.greenAccent : accentColor,
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

// ─────────────────────────────────────────
// Illustrations (pure Flutter drawing)
// ─────────────────────────────────────────

class _StepIllustration extends StatelessWidget {
  final _IllustrationType type;
  final Color accentColor;

  const _StepIllustration({required this.type, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case _IllustrationType.androidBrowser:
        return _AndroidBrowserIllustration(accentColor: accentColor);
      case _IllustrationType.androidMenu:
        return _AndroidMenuIllustration(accentColor: accentColor);
      case _IllustrationType.androidAddToHome:
        return _AndroidAddToHomeIllustration(accentColor: accentColor);
      case _IllustrationType.iosBrowser:
        return _IosBrowserIllustration(accentColor: accentColor);
      case _IllustrationType.iosShare:
        return _IosShareIllustration(accentColor: accentColor);
      case _IllustrationType.iosAddToHome:
        return _IosAddToHomeIllustration(accentColor: accentColor);
      case _IllustrationType.desktopBrowser:
        return _DesktopBrowserIllustration(accentColor: accentColor);
      case _IllustrationType.desktopInstallIcon:
        return _DesktopInstallIconIllustration(accentColor: accentColor);
      case _IllustrationType.desktopPrompt:
        return _DesktopPromptIllustration(accentColor: accentColor);
      case _IllustrationType.done:
        return _DoneIllustration(accentColor: accentColor);
    }
  }
}

// ── Shared phone frame widget ──

class _PhoneFrame extends StatelessWidget {
  final Widget child;
  const _PhoneFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              // notch
              Container(
                height: 8,
                color: const Color(0xFF1a1a2e),
                child: Center(
                  child: Container(
                    width: 20,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chrome address bar helper ──

Widget _chromeBar({Widget? trailingAction}) {
  return Container(
    height: 14,
    color: const Color(0xFF1F214F),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF2a2d6e),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (trailingAction != null) trailingAction,
        if (trailingAction == null)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (_) => Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.symmetric(vertical: 0.5),
                decoration: const BoxDecoration(
                  color: Colors.white38,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

// ── App content helper ──

Widget _appContentMock() {
  return Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1),
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 6),
        _shimmerLine(width: 50),
        const SizedBox(height: 4),
        _shimmerLine(width: 36),
      ],
    ),
  );
}

Widget _shimmerLine({double? width}) {
  return Container(
    width: width,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

// ─────────────────────────────────────────
// Individual illustrations
// ─────────────────────────────────────────

class _AndroidBrowserIllustration extends StatelessWidget {
  final Color accentColor;
  const _AndroidBrowserIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Column(
        children: [
          _chromeBar(),
          Expanded(child: _appContentMock()),
        ],
      ),
    );
  }
}

class _AndroidMenuIllustration extends StatelessWidget {
  final Color accentColor;
  const _AndroidMenuIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Stack(
        children: [
          Column(
            children: [
              _chromeBar(),
              Expanded(child: _appContentMock()),
            ],
          ),
          // dropdown menu overlay
          Positioned(
            top: 14,
            right: 0,
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2a2d6e),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  _menuItem('New tab'),
                  _menuItem('Bookmarks'),
                  _menuItemHighlight('Add to Home screen', accentColor),
                  _menuItem('Share...'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        label,
        style: const TextStyle(fontSize: 7, color: Colors.white60),
      ),
    );
  }

  Widget _menuItemHighlight(String label, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 7,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AndroidAddToHomeIllustration extends StatelessWidget {
  final Color accentColor;
  const _AndroidAddToHomeIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Stack(
        children: [
          Column(
            children: [
              _chromeBar(),
              Expanded(child: _appContentMock()),
            ],
          ),
          // dialog overlay
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  width: 58,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F214F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Divido',
                        style: TextStyle(
                          fontSize: 7,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Center(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Center(
                                child: Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 6,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosBrowserIllustration extends StatelessWidget {
  final Color accentColor;
  const _IosBrowserIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Column(
        children: [
          // Safari top bar
          Container(
            height: 14,
            color: const Color(0xFF1F214F),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2a2d6e),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _appContentMock()),
          // Safari bottom bar
          Container(
            height: 16,
            color: const Color(0xFF1F214F),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                4,
                (_) => Container(
                  width: 12,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosShareIllustration extends StatelessWidget {
  final Color accentColor;
  const _IosShareIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Stack(
        children: [
          Column(
            children: [
              Container(height: 14, color: const Color(0xFF1F214F)),
              Expanded(child: _appContentMock()),
              Container(
                height: 16,
                color: const Color(0xFF1F214F),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      width: 12,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // highlighted share button
                    Container(
                      width: 12,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.white38),
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IosAddToHomeIllustration extends StatelessWidget {
  final Color accentColor;
  const _IosAddToHomeIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _PhoneFrame(
      child: Stack(
        children: [
          Column(
            children: [
              Container(height: 14, color: const Color(0xFF1F214F)),
              Expanded(child: _appContentMock()),
              Container(height: 16, color: const Color(0xFF1F214F)),
            ],
          ),
          // share sheet from bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share',
                    style: TextStyle(fontSize: 7, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _iosShareItem('Copy', Colors.grey.shade400),
                      _iosShareItem('Add\nto HS', accentColor),
                      _iosShareItem('More', Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iosShareItem(String label, Color color) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 6, color: Colors.black54),
        ),
      ],
    );
  }
}

// ── Desktop frame helper ──

class _DesktopFrame extends StatelessWidget {
  final Widget child;
  final Widget? addressBarTrailing;

  const _DesktopFrame({required this.child, this.addressBarTrailing});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 110,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Column(
            children: [
              // title bar
              Container(
                height: 12,
                color: const Color(0xFF1F214F),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Row(
                      children: [
                        _dot(const Color(0xFFFF5F57)),
                        const SizedBox(width: 2),
                        _dot(const Color(0xFFFEBC2E)),
                        const SizedBox(width: 2),
                        _dot(const Color(0xFF28C840)),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          Container(
                            height: 7,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2a2d6e),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          if (addressBarTrailing != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: addressBarTrailing!,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _DesktopBrowserIllustration extends StatelessWidget {
  final Color accentColor;
  const _DesktopBrowserIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _DesktopFrame(child: _appContentMock());
  }
}

class _DesktopInstallIconIllustration extends StatelessWidget {
  final Color accentColor;
  const _DesktopInstallIconIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _DesktopFrame(
      addressBarTrailing: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: accentColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amber, width: 1),
        ),
      ),
      child: _appContentMock(),
    );
  }
}

class _DesktopPromptIllustration extends StatelessWidget {
  final Color accentColor;
  const _DesktopPromptIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return _DesktopFrame(
      child: Stack(
        children: [
          _appContentMock(),
          Positioned(
            top: 0,
            right: 4,
            child: Container(
              width: 56,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        'Install Divido?',
                        style: TextStyle(
                          fontSize: 6,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 6,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Center(
                            child: Text(
                              'Install',
                              style: TextStyle(
                                fontSize: 6,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneIllustration extends StatelessWidget {
  final Color accentColor;
  const _DoneIllustration({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Icon(Icons.check_rounded, color: Colors.white, size: 30),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Installed!',
            style: TextStyle(
              fontSize: 11,
              color: Colors.greenAccent.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
