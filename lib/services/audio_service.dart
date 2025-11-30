import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AudioService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> init() async {
    await _flutterTts.setLanguage("ar");
    await _flutterTts.setSpeechRate(0.5);

    if (Platform.isIOS) {
      await _flutterTts
          .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
          ]);
    }
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

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
  }
}
