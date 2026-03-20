import 'package:divido_app/screens/avatar_setup_page.dart';
import 'package:divido_app/screens/home.dart';
import 'package:divido_app/screens/login.dart';
import 'package:divido_app/screens/profile_page.dart';
import 'package:divido_app/screens/register_page.dart';
import 'package:divido_app/services/current_user.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'package:flutter/gestures.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Restore session if user was previously logged in
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: MaterialApp(
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
          // Dark background
          scaffoldBackgroundColor: const Color(0xFF171A3F),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF171A3F),
            foregroundColor: Colors.white, // title text color
            elevation: 0,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Colors.white, // button background
            foregroundColor: Color(0xFF171A3F), // icon color
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
        // home: const MyHomePage(title: 'Divido'),
        initialRoute: Supabase.instance.client.auth.currentSession != null ? '/home' : '/',
        routes: {
          '/': (context) => const LoginPage(),
          '/home': (context) => const HomePage(),
          '/login': (context) => const LoginPage(),
          '/register': (context) => const RegisterPage(),
          '/profile': (context) => const ProfilePage(),
          '/avatar-setup': (context) => const AvatarSetupPage(),
        },
      ),
    );
  }
}