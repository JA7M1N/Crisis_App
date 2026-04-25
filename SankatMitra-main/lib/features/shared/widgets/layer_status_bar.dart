import 'package:flutter/material.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';

class LayerStatusBar extends StatelessWidget {
  final ConnectivityLayer layer;

  const LayerStatusBar({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _layerColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _layerColor.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _layerColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _layerColor.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(_layerIcon, color: _layerColor, size: 16),
          const SizedBox(width: 8),
          Text(
            _layerLabel,
            style: TextStyle(
              color: _layerColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Color get _layerColor {
    switch (layer) {
      case ConnectivityLayer.firebase:
        return AppTheme.safeGreen;
      case ConnectivityLayer.sms:
        return AppTheme.accentOrange;
      case ConnectivityLayer.bluetooth:
        return AppTheme.alertBlue;
    }
  }

  IconData get _layerIcon {
    switch (layer) {
      case ConnectivityLayer.firebase:
        return Icons.cloud_done_rounded;
      case ConnectivityLayer.sms:
        return Icons.sms_rounded;
      case ConnectivityLayer.bluetooth:
        return Icons.bluetooth_rounded;
    }
  }

  String get _layerLabel {
    switch (layer) {
      case ConnectivityLayer.firebase:
        return 'LAYER 1 · FIREBASE REALTIME';
      case ConnectivityLayer.sms:
        return 'LAYER 2 · SMS FALLBACK';
      case ConnectivityLayer.bluetooth:
        return 'LAYER 3 · BLUETOOTH P2P';
    }
  }
}
