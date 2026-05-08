import 'package:divido_app/providers/group_provider.dart';
import 'package:divido_app/providers/status_provider.dart';
import 'package:divido_app/screens/avatar_setup_page.dart';
import 'package:divido_app/screens/email_confirmation_page.dart';
import 'package:divido_app/screens/forgot_password_page.dart';
import 'package:divido_app/screens/groups_page.dart';
import 'package:divido_app/screens/home.dart';
import 'package:divido_app/screens/install_guide_page.dart';
import 'package:divido_app/screens/landing_page.dart';
import 'package:divido_app/screens/login.dart';
import 'package:divido_app/screens/profile_page.dart';
import 'package:divido_app/screens/register_page.dart';
import 'package:divido_app/screens/reset_password_page.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final session = Supabase.instance.client.auth.currentSession;
  if (session != null) {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', session.user.id)
        .single();
    CurrentUser.instance.setFromMap(profile);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Listen here — navigator is guaranteed to exist after first frame
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/reset-password',
          (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final initialRoute = Supabase.instance.client.auth.currentSession != null
        ? '/home'
        : '/';

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => StatusProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Divido',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF171A3F),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F1128),
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF171A3F),
          ),
          textTheme: const TextTheme(
            bodyMedium: TextStyle(color: Colors.white),
            bodyLarge: TextStyle(color: Colors.white),
            bodySmall: TextStyle(color: Colors.white),
            headlineMedium: TextStyle(color: Colors.white),
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            brightness: Brightness.dark,
          ),
        ),
        initialRoute: initialRoute,
        routes: {
          '/': (context) => const LandingPage(),
          '/login': (context) => const LoginPage(),
          '/home': (context) => const HomePage(),
          '/register': (context) => const RegisterPage(),
          '/profile': (context) => const ProfilePage(),
          '/avatar-setup': (context) => const AvatarSetupPage(),
          '/email-confirm': (context) => const EmailConfirmationPage(),
          '/groups': (context) => const GroupsPage(),
          '/install-guide': (context) => const InstallGuidePage(),
          '/forgot-password': (context) => const ForgotPasswordPage(),
          '/reset-password': (context) => const ResetPasswordPage(),
        },
      ),
    );
  }
}
