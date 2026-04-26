import 'package:flutter/material.dart';

class TermsDialog extends StatelessWidget {
  const TermsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFF171A3F),
      title: Row(
        children: const [
          Icon(Icons.gavel_rounded, color: Colors.white, size: 22),
          SizedBox(width: 8),
          Text(
            "Terms & Conditions",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Last updated: April 2026\n\n'
                      'Welcome to Divido.\n\n'
                      'By using Divido, you agree to the following terms:\n',
                    ),
                    _section('1. What Divido Does',
                        'Divido is an expense-splitting and tracking app. It helps users:\n\n'
                        '• Record shared expenses\n'
                        '• Track balances within groups\n'
                        '• Organize who owes whom\n\n'
                        'Divido does not handle or process actual payments.'),
                    _section('2. No Financial Responsibility',
                        'Divido is provided for tracking purposes only.\n\n'
                        '• We do not guarantee that balances are always accurate\n'
                        '• We are not responsible for disputes between users\n'
                        '• Users are responsible for verifying expenses and payments\n\n'
                        'You agree that any real-world transactions are your own responsibility.'),
                    _section('3. User Accounts',
                        'When creating an account, you agree to:\n\n'
                        '• Provide accurate information\n'
                        '• Keep your login credentials secure\n'
                        '• Not share your account with others\n\n'
                        'You are responsible for all activity under your account.'),
                    _section('4. Group Usage',
                        'Groups are created and managed by users.\n\n'
                        '• Group creators may manage members and group settings\n'
                        '• Members are responsible for their own entries and actions\n'
                        '• We are not responsible for misuse within groups'),
                    _section('5. Data and Changes',
                        'We may:\n\n'
                        '• Update or improve features\n'
                        '• Modify or remove parts of the app\n'
                        '• Fix bugs or reset data if necessary\n\n'
                        'We do not guarantee uninterrupted or error-free service.'),
                    _section('6. Termination',
                        'We may suspend or remove access if:\n\n'
                        '• The app is abused\n'
                        '• There is harmful or inappropriate behavior'),
                    _section('7. Acceptance',
                        'By using Divido, you agree to these terms.\n\n'
                        '---\n'),
                    const Text(
                      'Privacy Policy\n\n'
                      'Last updated: April 2026\n\n'
                      'Your privacy matters. This policy explains what data Divido collects and how it is used.\n',
                    ),
                    _section('1. Information We Collect',
                        'We collect only what is needed for the app to function:\n\n'
                        'Account Information\n'
                        '• Username\n'
                        '• Password (securely handled via authentication system)\n\n'
                        'Profile Information\n'
                        '• Name\n'
                        '• Contact number (optional)\n'
                        '• GCash number (optional)\n'
                        '• Profile photo (optional)\n\n'
                        'App Data\n'
                        '• Expenses\n'
                        '• Payments\n'
                        '• Group memberships\n'
                        '• Notes and statuses'),
                    _section('2. How We Use Your Data',
                        'We use your data to:\n\n'
                        '• Provide expense tracking features\n'
                        '• Show balances and group activity\n'
                        '• Improve user experience\n'
                        '• Maintain app functionality\n\n'
                        'We do not sell your data.'),
                    _section('3. Data Storage',
                        'Your data is stored securely using backend services (e.g., Supabase).\n\n'
                        'We take reasonable steps to protect your data, but no system is 100% secure.'),
                    _section('4. Payments Disclaimer',
                        'Divido does not process payments.\n\n'
                        '• GCash or contact numbers are stored only for convenience\n'
                        '• Any payment done outside the app is between users'),
                    _section('5. Your Control',
                        'You can:\n\n'
                        '• Edit your profile information\n'
                        '• Update or remove data you entered\n'
                        '• Leave groups\n\n'
                        'Some data may remain as part of shared group records.'),
                    _section('6. Data Retention',
                        'We keep data as long as needed for the app to function.\n\n'
                        'You may request deletion by contacting the developer (if applicable).'),
                    _section('7. Changes to This Policy',
                        'We may update this policy as the app evolves.'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(content),
        ],
      ),
    );
  }
}
