import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';

/// Full-width animated banner that appears whenever the connectivity layer
/// changes. Shows for [displayDuration] then slides back up automatically.
class LayerAlertBanner extends StatefulWidget {
  final Stream<ConnectivityLayer> layerStream;
  final Duration displayDuration;

  const LayerAlertBanner({
    super.key,
    required this.layerStream,
    this.displayDuration = const Duration(seconds: 5),
  });

  @override
  State<LayerAlertBanner> createState() => _LayerAlertBannerState();
}

class _LayerAlertBannerState extends State<LayerAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  StreamSubscription? _sub;
  Timer? _hideTimer;

  ConnectivityLayer? _layer;
  bool _visible = false;

  // Track previous to detect actual changes
  ConnectivityLayer? _prevLayer;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _sub = widget.layerStream.listen(_onLayerChange);
  }

  void _onLayerChange(ConnectivityLayer layer) {
    // Skip the very first emission (startup, not a real switch)
    if (_prevLayer == null) {
      _prevLayer = layer;
      return;
    }
    if (layer == _prevLayer) return;
    _prevLayer = layer;

    _hideTimer?.cancel();
    setState(() {
      _layer = layer;
      _visible = true;
    });
    _slideCtrl.forward(from: 0);

    _hideTimer = Timer(widget.displayDuration, () {
      if (mounted) {
        _slideCtrl.reverse().then((_) {
          if (mounted) setState(() => _visible = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    _slideCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _layer == null) return const SizedBox.shrink();

    final config = _bannerConfig(_layer!);

    return SlideTransition(
      position: _slideAnim,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            color: config.color.withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            boxShadow: [
              BoxShadow(
                color: config.color.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            children: [
              // Animated pulse icon
              _PulseIcon(icon: config.icon, color: config.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      config.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      config.subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Layer badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Text(
                  config.badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _BannerConfig _bannerConfig(ConnectivityLayer layer) {
    switch (layer) {
      case ConnectivityLayer.cloud:
        return _BannerConfig(
          color: const Color(0xFF00C853),
          icon: Icons.cloud_done_rounded,
          title: 'CLOUD SYNC RESTORED',
          subtitle: 'Internet connected — syncing all positions via Supabase',
          badge: 'CLOUD',
        );
      case ConnectivityLayer.bluetooth:
        return _BannerConfig(
          color: const Color(0xFF2979FF),
          icon: Icons.hub_rounded,
          title: '⚠️ ACTIVATING P2P MESH',
          subtitle: 'No internet — switching to Bluetooth mesh network',
          badge: 'P2P MESH',
        );
      case ConnectivityLayer.sms:
        return _BannerConfig(
          color: const Color(0xFFFF6D00),
          icon: Icons.sms_failed_rounded,
          title: '🚨 ALL DATA LOST — SMS FALLBACK',
          subtitle: 'No internet or Bluetooth — broadcasting via SMS',
          badge: 'SMS',
        );
    }
  }
}

class _BannerConfig {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  const _BannerConfig({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
  });
}

class _PulseIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  const _PulseIcon({required this.icon, required this.color});

  @override
  State<_PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<_PulseIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.15)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, color: Colors.white, size: 20),
      ),
    );
  }
}