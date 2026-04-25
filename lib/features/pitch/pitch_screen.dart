import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sankatmitra/core/routes/app_router.dart';

/// Full-screen pitch slide shown once (or always in demo mode).
/// Communicates the problem → solution → key features in ~8 seconds,
/// then auto-advances to role selection. User can also tap to skip.
class PitchScreen extends StatefulWidget {
  const PitchScreen({super.key});

  @override
  State<PitchScreen> createState() => _PitchScreenState();
}

class _PitchScreenState extends State<PitchScreen>
    with TickerProviderStateMixin {
  // ── Slide content ────────────────────────────────────────────────────────
  static const _slides = [
    _Slide(
      stat: '87%',
      statLabel: 'of disaster victims',
      body: 'lose cellular connectivity\nwithin 2 hours of a crisis.',
      icon: Icons.signal_cellular_off_rounded,
      color: Color(0xFFE53935),
    ),
    _Slide(
      stat: '3 Layers',
      statLabel: 'of communication',
      body: 'Cloud  →  P2P Mesh  →  SMS\nSankatMitra never goes silent.',
      icon: Icons.layers_rounded,
      color: Color(0xFF2979FF),
    ),
    _Slide(
      stat: 'AI Triage',
      statLabel: 'powered by Gemini',
      body: 'Victims describe their situation.\nResponders see P0 → P3 priority instantly.',
      icon: Icons.psychology_rounded,
      color: Color(0xFF7C4DFF),
    ),
    _Slide(
      stat: '0 Infra',
      statLabel: 'required',
      body: 'No servers. No towers. No power.\nJust phones talking to phones.',
      icon: Icons.offline_bolt_rounded,
      color: Color(0xFF00C853),
    ),
  ];

  int _current = 0;
  late PageController _pageCtrl;
  Timer? _autoTimer;

  late AnimationController _statCtrl;
  late AnimationController _fadeCtrl;
  late AnimationController _bgCtrl;
  late Animation<double> _statScale;
  late Animation<double> _fadeAnim;
  late Animation<double> _bgRotate;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();

    _statCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _statScale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _statCtrl, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn),
    );
    _bgRotate = Tween<double>(begin: 0, end: 2 * pi).animate(_bgCtrl);

    _statCtrl.forward();
    _fadeCtrl.forward();

    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = Timer(const Duration(seconds: 3), _nextSlide);
  }

  void _nextSlide() {
    if (_current < _slides.length - 1) {
      _current++;
      _pageCtrl.animateToPage(
        _current,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      _statCtrl.forward(from: 0);
      _fadeCtrl.forward(from: 0);
      _startAutoAdvance();
    } else {
      _goToApp();
    }
  }

  void _goToApp() {
    _autoTimer?.cancel();
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRouter.roleSelection);
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    _statCtrl.dispose();
    _fadeCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_current];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF060B16),
      body: GestureDetector(
        onTapDown: (_) {
          _autoTimer?.cancel();
          _nextSlide();
        },
        child: Stack(
          children: [
            // ── Animated background geometry ─────────────────────────────
            AnimatedBuilder(
              animation: _bgRotate,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _BgPainter(_bgRotate.value, slide.color),
              ),
            ),

            // ── Slide pages ──────────────────────────────────────────────
            PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _slides.length,
              itemBuilder: (_, i) => const SizedBox.shrink(),
            ),

            // ── Main content ─────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // App name header
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935).withOpacity(0.5),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.crisis_alert_rounded,
                              size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'SankatMitra',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Spacer(),
                        // Skip button
                        TextButton(
                          onPressed: _goToApp,
                          child: Text(
                            'SKIP',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ── Stat number ─────────────────────────────────────
                    ScaleTransition(
                      scale: _statScale,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          slide.stat,
                          key: ValueKey(slide.stat),
                          style: TextStyle(
                            fontSize: 88,
                            fontWeight: FontWeight.w900,
                            color: slide.color,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: slide.color.withOpacity(0.5),
                                blurRadius: 40,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        children: [
                          Text(
                            slide.statLabel.toUpperCase(),
                            style: TextStyle(
                              color: slide.color.withOpacity(0.8),
                              fontSize: 13,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Icon
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: slide.color.withOpacity(0.12),
                              border: Border.all(
                                color: slide.color.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(slide.icon,
                                color: slide.color, size: 32),
                          ),

                          const SizedBox(height: 28),

                          // Body text
                          Text(
                            slide.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 16,
                              height: 1.6,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // ── Progress dots ────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slides.length, (i) {
                        final active = i == _current;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: active ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? slide.color
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 20),

                    // ── CTA ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Text(
                        _current < _slides.length - 1
                            ? 'Tap to continue'
                            : 'Tap to get started',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ──────────────────────────────────────────────────────────────

class _Slide {
  final String stat;
  final String statLabel;
  final String body;
  final IconData icon;
  final Color color;
  const _Slide({
    required this.stat,
    required this.statLabel,
    required this.body,
    required this.icon,
    required this.color,
  });
}

// ── Background painter ───────────────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  final double angle;
  final Color color;
  _BgPainter(this.angle, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.42;

    // Rotating ring lines
    final paint = Paint()
      ..color = color.withOpacity(0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 6; i++) {
      final r = 80.0 + i * 60;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }

    // Rotating radar sweep
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.12), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 260))
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawArc(
      const Rect.fromLTWH(-260, -260, 520, 520),
      -0.3,
      0.6,
      true,
      sweepPaint,
    );
    canvas.restore();

    // Grid
    final gridPaint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.angle != angle || old.color != color;
}