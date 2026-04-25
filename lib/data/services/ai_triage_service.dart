import 'dart:convert';
import 'package:http/http.dart' as http;

/// AI Incident Triage using Google Gemini 1.5 Flash (FREE tier)
/// Free tier: 15 requests/min, 1 million tokens/day — more than enough for emergencies
///
/// SETUP: Get your free API key at https://aistudio.google.com/app/apikey
/// Replace the placeholder below — no billing required for the free tier.

class AiTriageService {
  static final AiTriageService _instance = AiTriageService._internal();
  factory AiTriageService() => _instance;
  AiTriageService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // Get FREE key at: https://aistudio.google.com/app/apikey (no credit card)
  // ─────────────────────────────────────────────────────────────────────────
  static const String _apiKey = 'YOUR_GEMINI_API_KEY';
  static const String _model = 'gemini-1.5-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// Scores an incident description and returns P0–P3 priority
  ///
  /// P0 = Immediate threat to life (fire, unconscious, cardiac arrest)
  /// P1 = Serious injury or danger (broken bones, trapped, bleeding)
  /// P2 = Moderate distress (stranded, minor injuries, shelter needed)
  /// P3 = Low urgency (lost, needs assistance, no immediate danger)
  ///
  /// Returns empty string if API key not configured or request fails.
  Future<String> triageIncident(String description) async {
    if (_apiKey == 'YOUR_GEMINI_API_KEY' || _apiKey.isEmpty) {
      // AI triage not configured — return empty, app still works fine
      return '';
    }
    if (description.trim().isEmpty) return '';

    try {
      final prompt = '''
You are an emergency dispatcher. Classify this incident into ONE priority level.

Incident: "$description"

Priority levels:
- P0: Immediate life threat (fire, unconscious, cardiac arrest, drowning, severe bleeding, building collapse with trapped people)
- P1: Serious but stable (significant injuries, trapped but breathing, structural damage with people inside)
- P2: Moderate (stranded, minor injuries, needs evacuation, distressed but safe for now)
- P3: Low urgency (lost, needs assistance, no immediate physical danger)

Reply with ONLY the priority code: P0, P1, P2, or P3. Nothing else.
''';

      final response = await http
          .post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'maxOutputTokens': 4,
            'temperature': 0.0, // deterministic for triage
          },
        }),
      )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
            ?.toString()
            .trim()
            .toUpperCase() ??
            '';
        // Validate it's a real priority code
        if (['P0', 'P1', 'P2', 'P3'].contains(text)) return text;
      }
      return '';
    } catch (_) {
      // Network error or timeout — fail silently, SOS still goes through
      return '';
    }
  }

  /// Returns a Color hex string for a priority code (for use in UI)
  static String priorityColor(String priority) {
    switch (priority) {
      case 'P0': return '#E53935'; // red
      case 'P1': return '#FF6D00'; // orange
      case 'P2': return '#FFB300'; // amber
      case 'P3': return '#00C853'; // green
      default:   return '#9CA3AF'; // gray (unknown)
    }
  }

  static String priorityLabel(String priority) {
    switch (priority) {
      case 'P0': return 'CRITICAL';
      case 'P1': return 'SERIOUS';
      case 'P2': return 'MODERATE';
      case 'P3': return 'LOW';
      default:   return 'UNRATED';
    }
  }
}