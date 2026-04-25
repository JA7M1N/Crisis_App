import 'package:flutter/material.dart';
import 'package:sankatmitra/data/services/connectivity_service.dart';
import 'package:sankatmitra/core/theme/app_theme.dart';

class LayerStatusBar extends StatelessWidget {
  final ConnectivityLayer layer;

  const LayerStatusBar({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    final config = _layerConfig(layer);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: config.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: config.color.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: config.color.withOpacity(0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: config.color,
              boxShadow: [
                BoxShadow(
                  color: config.color,
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(config.icon, color: config.color, size: 14),
          const SizedBox(width: 6),
          Text(
            config.label,
            style: TextStyle(
              color: config.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  _LayerConfig _layerConfig(ConnectivityLayer layer) {
    switch (layer) {
      case ConnectivityLayer.cloud:
        return _LayerConfig(
          color: AppTheme.alertBlue,
          icon: Icons.cloud_done_rounded,
          label: 'CLOUD SYNC',
        );
      case ConnectivityLayer.bluetooth:
        return _LayerConfig(
          color: const Color(0xFF7C4DFF),
          icon: Icons.bluetooth_rounded,
          label: 'MESH P2P',
        );
      case ConnectivityLayer.sms:
        return _LayerConfig(
          color: AppTheme.accentOrange,
          icon: Icons.sms_rounded,
          label: 'SMS FALLBACK',
        );
    }
  }
}

class _LayerConfig {
  final Color color;
  final IconData icon;
  final String label;

  _LayerConfig({required this.color, required this.icon, required this.label});
}
