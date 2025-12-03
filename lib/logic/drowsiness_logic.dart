import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DrowsinessLogic {
  // --- THRESHOLDS ---
  static const double _EYE_OPEN_THRESHOLD = 0.4;
  static const double _HEAD_YAW_THRESHOLD = 25.0;
  static const double _HEAD_PITCH_THRESHOLD = 20.0;

  // --- SETTINGS ---
  static const int _SLEEP_FRAMES = 50;
  static const int _TIME_THRESHOLD_MS = 1500; // 1.5 Seconds (1500 ms)

  // --- COUNTERS & TIMERS ---
  int _closedFrames = 0;

  // We use timestamps to measure exactly 1.5 seconds regardless of FPS
  DateTime? _distractedStartTime;
  DateTime? _drowsyStartTime;

  String checkFace(Face face) {
    // 1. ANALYZE FACE DATA
    // Distraction (Head Pose)
    bool isDistracted = false;
    if ((face.headEulerAngleY ?? 0).abs() > _HEAD_YAW_THRESHOLD) isDistracted = true;
    if ((face.headEulerAngleX ?? 0).abs() > _HEAD_PITCH_THRESHOLD) isDistracted = true;

    // Eyes Closed
    bool isLeftEyeClosed = (face.leftEyeOpenProbability ?? 1.0) < _EYE_OPEN_THRESHOLD;
    bool isRightEyeClosed = (face.rightEyeOpenProbability ?? 1.0) < _EYE_OPEN_THRESHOLD;
    bool isEyesClosed = isLeftEyeClosed && isRightEyeClosed;

    // 2. LOGIC PROCESSING

    // --- CASE A: EYES CLOSED (Sleep/Drowsy) ---
    if (isEyesClosed) {
      _closedFrames++;
      _distractedStartTime = null; // Reset distraction if eyes are closed

      // Start Drowsy Timer if not started
      _drowsyStartTime ??= DateTime.now();

      // PRIORITY 1: DEEP SLEEP (Frame-based for safety backup)
      if (_closedFrames > _SLEEP_FRAMES) {
        return "ASLEEP";
      }

      // PRIORITY 2: DROWSY (Time-based: 2 Seconds)
      if (DateTime.now().difference(_drowsyStartTime!).inMilliseconds > _TIME_THRESHOLD_MS) {
        return "DROWSY";
      }

      // If closed but not for 2 seconds yet, we consider them still AWAKE (blinking)
      return "AWAKE";
    }
    else {
      // Eyes are OPEN
      _closedFrames = 0;
      _drowsyStartTime = null; // Reset drowsy timer

      // --- CASE B: DISTRACTION (Looking Away) ---
      if (isDistracted) {
        // Start Timer if not started
        _distractedStartTime ??= DateTime.now();

        // Check if 2 seconds have passed
        if (DateTime.now().difference(_distractedStartTime!).inMilliseconds > _TIME_THRESHOLD_MS) {
          return "DISTRACTED";
        }
      } else {
        // Looking straight ahead
        _distractedStartTime = null; // Reset timer
      }
    }

    return "AWAKE";
  }
}