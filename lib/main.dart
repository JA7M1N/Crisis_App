import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION: Replace with your free Supabase project credentials
// Get a free project at https://supabase.com (no credit card required)
// ─────────────────────────────────────────────────────────────────────────────
const String supabaseUrl = 'https://mjbvncxqhteuvnafgpo.supabase.co';       // e.g. https://xxxx.supabase.co
const String supabaseAnonKey = 'sb_publishable_W9bLdeZPAFsMD-8ahA6WEg_NAEzyDnF'; // Found in Project Settings > API

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.info,
    ),
  );

  runApp(const SankatMitraApp());
}

class SankatMitraApp extends StatelessWidget {
  const SankatMitraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SankatMitra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
