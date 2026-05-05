// lib/constants/app_config.dart
import 'package:flutter/foundation.dart';

// kReleaseMode is true in release builds (e.g. flutter build web), false in debug/profile (flutter run)
const String kRedirectUrl = kReleaseMode
    ? 'https://divido-app.vercel.app/'
    : 'http://localhost:3000/';