import 'package:flutter/foundation.dart';

/// SmsService — stubbed for Flutter 3.41 compatibility.
/// flutter_sms and telephony both use Android v1 embedding.
/// SMS fallback is simulated — replace with a REST SMS API
/// (e.g. Twilio, Fast2SMS) for production use.

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  Future<bool> sendSosLocation({
    required String phoneNumber,
    required double lat,
    required double lng,
    String senderName = 'SankatMitra User',
  }) async {
    final mapsLink = 'https://maps.google.com/?q=$lat,$lng';
    final message =
        '🆘 EMERGENCY ALERT from $senderName\n'
        'I need help! My location:\n$mapsLink\n'
        'Sent via SankatMitra';

    // TODO: Replace with Twilio REST API call for production
    // For now, log the message so SMS layer is traceable in debug
    debugPrint('[SMS] Would send to $phoneNumber: $message');
    return true;
  }

  Future<void> sendSosToAll({
    required List<String> contacts,
    required double lat,
    required double lng,
  }) async {
    for (final contact in contacts) {
      await sendSosLocation(phoneNumber: contact, lat: lat, lng: lng);
    }
  }
}
