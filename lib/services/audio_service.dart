import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();

  bool _isListening = false;

  Future<void> init() async {
    // 1. Setup TTS (Voice)
    try {
      await _flutterTts.setLanguage("ar");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);

      // Check if language is available
      var isLanguageAvailable = await _flutterTts.isLanguageAvailable("ar");
      print("TTS: Arabic language available: $isLanguageAvailable");

      if (Platform.isIOS) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers
          ],
        );
      }
    } catch (e) {
      print("TTS Init Error: $e");
    }

    // 2. Setup STT (Microphone)
    bool available = await _speechToText.initialize(
      onError: (val) => print('STT Error: $val'),
      onStatus: (val) => print('STT Status: $val'),
    );
    if (!available) {
      print("Speech recognition not available");
    }
  }

  // --- TTS (Speaking) ---
  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      print("TTS: Attempting to speak: $text");
      await _flutterTts.stop();
      var result = await _flutterTts.speak(text);
      if (result == 1) {
        print("TTS: Speak command successful");
      } else {
        print("TTS: Speak command failed");
      }
    }
  }

  // --- STT (Listening) ---
  Future<void> listen(Function(String) onResult) async {
    if (!_isListening) {
      bool available = await _speechToText.initialize();
      if (available) {
        _isListening = true;
        _speechToText.listen(
          onResult: (val) {
            if (val.finalResult) {
              _isListening = false;
              stopListening();
              onResult(val.recognizedWords);
            }
          },
          localeId: "ar_SA",
          listenFor: const Duration(seconds: 10),
          pauseFor: const Duration(seconds: 3),
        );
      }
    } else {
      stopListening();
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _speechToText.stop();
  }

  // --- Alarm ---
  Future<void> playAlarm() async {
    if (_audioPlayer.state == PlayerState.playing) return;
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.setSource(AssetSource('sounds/alarm.mp3'));
    await _audioPlayer.resume();
    await _audioPlayer.setVolume(1.0);
  }

  Future<void> stopAll() async {
    await _audioPlayer.stop();
    await _flutterTts.stop();
    await stopListening();
  }
}