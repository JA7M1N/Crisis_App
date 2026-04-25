import 'package:telephony/telephony.dart';

class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  final Telephony _telephony = Telephony.instance;

  /// Send an SOS SMS with location link to a given number
  Future<bool> sendSosLocation({
    required String phoneNumber,
    required double lat,
    required double lng,
    String senderName = 'CrisisLink User',
  }) async {
    try {
      final bool? permGranted = await _telephony.requestSmsPermissions;
      if (permGranted != true) return false;

      final mapsLink = 'https://maps.google.com/?q=$lat,$lng';
      final message =
          '🆘 EMERGENCY ALERT from $senderName\n'
          'I need help! My location:\n$mapsLink\n'
          'Sent via CrisisLink';

      await _telephony.sendSms(
        to: phoneNumber,
        message: message,
        statusListener: (SendStatus status) {
          // Status handling
        },
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Send SOS to multiple contacts
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
