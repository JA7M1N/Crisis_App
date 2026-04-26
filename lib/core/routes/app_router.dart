import 'package:flutter/material.dart';
import 'package:sankatmitra/features/splash/splash_screen.dart';
import 'package:sankatmitra/features/pitch/pitch_screen.dart';
import 'package:sankatmitra/features/role_selection/role_selection_screen.dart';
import 'package:sankatmitra/features/home/home_screen.dart';
import 'package:sankatmitra/features/dashboard/coordinator_dashboard.dart';
import 'package:sankatmitra/data/models/user_model.dart';

class AppRouter {
  static const String splash = '/';
  static const String pitch = '/pitch';
  static const String roleSelection = '/role-selection';
  static const String home = '/home';
  static const String dashboard = '/dashboard';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fadeRoute(const SplashScreen(), settings);

      case pitch:
        return _fadeRoute(const PitchScreen(), settings);

      case roleSelection:
        return _fadeRoute(const RoleSelectionScreen(), settings);

      case home:
        final user = settings.arguments as UserModel?;
        return _slideRoute(HomeScreen(user: user), settings);

      case dashboard:
        // ── FIX: Accept UserModel from coordinator role selection ──
        // If a UserModel is passed, use its sessionId and name.
        // If navigated to directly (e.g. from HomeScreen icon), no args needed
        // — dashboard falls back to streaming all sessions.
        final args = settings.arguments;
        if (args is UserModel) {
          return _slideRoute(
            CoordinatorDashboard(
              sessionId: args.sessionId,
              coordinatorName: args.displayName,
            ),
            settings,
          );
        }
        // No args — show all sessions (global coordinator view)
        return _slideRoute(const CoordinatorDashboard(), settings);

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 500),
    );
  }

  static PageRouteBuilder _slideRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final tween = Tween(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(
            position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 400),
    );
  }
}
