import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/core/routes/app_router.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CrisisLinkApp());
}

class CrisisLinkApp extends StatelessWidget {
  const CrisisLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrisisLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
