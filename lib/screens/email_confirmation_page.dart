import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:divido_app/services/current_user.dart';

class EmailConfirmationPage extends StatefulWidget {
  const EmailConfirmationPage({super.key});

  @override
  State<EmailConfirmationPage> createState() => _EmailConfirmationPageState();
}

class _EmailConfirmationPageState extends State<EmailConfirmationPage> {
  bool _isChecking = false;
  bool _isResending = false;
  String? _message;

  Future<void> _checkConfirmation() async {
    setState(() {
      _isChecking = true;
      _message = null;
    });

    try {
      // refresh session to get latest user state
      await Supabase.instance.client.auth.refreshSession();
      final user = Supabase.instance.client.auth.currentUser;

      if (user?.emailConfirmedAt != null) {
        // confirmed — fetch profile and proceed
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', user!.id)
            .single();

        CurrentUser.instance.setFromMap(profile);

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/avatar-setup');
        }
      } else {
        setState(() => _message = 'Email not confirmed yet. Check your inbox.');
      }
    } catch (e) {
      setState(() => _message = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isResending = true;
      _message = null;
    });

    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) return;

      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );

      setState(() => _message = 'Confirmation email resent!');
    } catch (e) {
      setState(() => _message = 'Failed to resend. Try again.');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              // icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withValues(alpha: 0.12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 36,
                  color: Colors.blue.shade300,
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'Check your email',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'We sent a confirmation link to',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 4),

              Text(
                email,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'Click the link in the email to confirm\nyour account, then come back here.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // error/success message
              if (_message != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _message!.contains('not') || _message!.contains('wrong') || _message!.contains('Failed')
                        ? Colors.red.withValues(alpha: 0.08)
                        : Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _message!.contains('not') || _message!.contains('wrong') || _message!.contains('Failed')
                          ? Colors.red.withValues(alpha: 0.25)
                          : Colors.green.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _message!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _message!.contains('not') || _message!.contains('wrong') || _message!.contains('Failed')
                          ? Colors.red.shade400
                          : Colors.green.shade400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // I've confirmed button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkConfirmation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF171A3F),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF171A3F),
                          ),
                        )
                      : const Text(
                          "I've confirmed my email",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // resend button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isResending ? null : _resendEmail,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isResending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Resend confirmation email',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}