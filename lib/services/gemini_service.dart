import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // ⚠️ REPLACE WITH YOUR ACTUAL API KEY
  static const String _apiKey = 'AIzaSyDQS1F6Jd2cq74PFLbob4ondu24ENf_G0w';

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-pro', // FIXED: Switched to 'gemini-pro' to fix "Not Found" error
      apiKey: _apiKey,
    );
  }

  Future<String> getIntervention(String state) async {
    String prompt;
    switch (state) {
      case "DISTRACTED":
        prompt = "Respond in Arabic. Tell the driver to look at the road. Max 3 words.";
        break;
      case "DROWSY":
        prompt = "Respond in Arabic. Warn the driver they are sleeping. Max 4 words.";
        break;
      case "ASLEEP":
        prompt = "Respond in Arabic. Scream WAKE UP! Max 2 words.";
        break;
      default:
        prompt = "Say Hello in Arabic";
    }

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "خطأ في النص";
    } catch (e) {
      print("❌ GEMINI ERROR: $e");
      // If error persists, fallback to static text so the app doesn't break
      if (state == "ASLEEP") return "استيقظ فوراً!";
      return "الرجاء الانتباه";
    }
  }
}