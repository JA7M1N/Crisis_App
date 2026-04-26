import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// SilentPanicService — vol-down ×3 within 2 seconds → silent SOS.
/// Uses Flutter's built-in HardwareKeyboard API. No native packages needed.

class SilentPanicService {
  static final SilentPanicService _instance = SilentPanicService._internal();
  factory SilentPanicService() => _instance;
  SilentPanicService._internal();

  static const int _requiredPresses = 3;
  static const int _windowMs = 2000;

  final List<DateTime> _presses = [];
  void Function()? _callback;
  bool _active = false;

  void startListening(void Function() callback) {
    _callback = callback;
    _active = true;
    _presses.clear();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    debugPrint('[SilentPanic] Listening — vol-down ×$_requiredPresses triggers SOS');
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!_active) return false;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
      final now = DateTime.now();
      _presses.removeWhere(
          (t) => now.difference(t) > const Duration(milliseconds: _windowMs));
      _presses.add(now);
      debugPrint('[SilentPanic] Press #${_presses.length}/$_requiredPresses');
      if (_presses.length >= _requiredPresses) {
        _presses.clear();
        _triggerSilentSOS();
      }
      return true; // consume the event
    }
    return false;
  }

  void _triggerSilentSOS() {
    _tripleVibrate();
    debugPrint('[SilentPanic] 🔇 Silent SOS triggered!');
    _callback?.call();
  }

  Future<void> _tripleVibrate() async {
    for (int i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  void stopListening() {
    _active = false;
    _callback = null;
    _presses.clear();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    debugPrint('[SilentPanic] Stopped');
  }
}
