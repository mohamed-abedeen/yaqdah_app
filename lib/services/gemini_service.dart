import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // ⚠️ YOUR API KEY
  static const String _apiKey = 'AIzaSyAcXBUVKOIzgJJBId0MIgcGdOje0KxyJm0';

  late GenerativeModel _model;

  // Track the current model name locally since GenerativeModel doesn't expose it
  String _currentModelName = 'gemini-2.5-flash';

  GeminiService() {
    // Start with the standard Flash model
    _model = GenerativeModel(
      model: _currentModelName,
      apiKey: _apiKey,
    );

    // Attempt to validate access immediately
    _checkModelAccess();
  }

  // --- DIAGNOSTIC TOOL ---
  Future<void> _checkModelAccess() async {
    try {
      // We send a dummy prompt to see if the model is reachable
      print("GeminiService: Testing model access for $_currentModelName...");
      final testContent = [Content.text("Test")];
      await _model.generateContent(testContent);
      print("GeminiService: ✅ Access Confirmed for $_currentModelName");
    } catch (e) {
      print("GeminiService: ❌ Access Failed for $_currentModelName. Error: $e");

      // If Flash fails, fallback to Pro
      if (e.toString().contains("404") || e.toString().contains("not found")) {
        print("GeminiService: 🔄 Switching to 'gemini-pro' as fallback...");

        _currentModelName = 'gemini-pro'; // Update our local tracker
        _model = GenerativeModel(
          model: _currentModelName,
          apiKey: _apiKey,
        );
      }
    }
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
        prompt = "Respond in Arabic. Urgently tell the driver to wake up. Max 2 words.";
        break;
      default:
        prompt = "Say Hello in Arabic";
    }
    return _sendPrompt(prompt);
  }

  Future<String> chatWithDriver(String userMessage) async {
    String prompt =
        "Act as a helpful car co-pilot. The driver is speaking to you in Arabic.\n"
        "Driver said: '$userMessage'\n"
        "Reply in helpful, short Arabic (max 1 sentence).";

    return _sendPrompt(prompt);
  }

  Future<String> _sendPrompt(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "لا يوجد رد";
    } catch (e) {
      print("❌ GEMINI ERROR DETAILED: $e");

      if (e.toString().contains("404") || e.toString().contains("not found")) {
        return "خطأ: الموديل غير موجود (404). تأكد من المفتاح.";
      }
      if (e.toString().contains("403")) {
        return "خطأ: مفتاح API غير صالح (403)";
      }
      if (e.toString().contains("User location is not supported")) {
        return "خطأ: الخدمة غير متوفرة في منطقتك";
      }

      return "خطأ في الاتصال: $e";
    }
  }
}