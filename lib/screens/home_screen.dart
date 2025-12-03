import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logic/drowsiness_logic.dart';
import '../services/gemini_service.dart';
import '../services/audio_service.dart';
import '../services/location_sms_service.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- CORE CONTROLLERS ---
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: false,
    ),
  );

  final DrowsinessLogic _logic = DrowsinessLogic();
  final GeminiService _gemini = GeminiService();
  final AudioService _audio = AudioService();
  final LocationSmsService _smsService = LocationSmsService();

  // --- STATE VARIABLES ---
  bool _isProcessing = false;
  bool _isMonitoring = true;
  bool _showCameraFeed = false;

  // Logic State
  String _status = "AWAKE";
  String _aiMessage = "System Active";
  DateTime _lastAiTrigger = DateTime.now();
  bool _smsSent = false;
  bool _isListening = false;

  // UI State
  int _tripDurationSeconds = 0;
  Timer? _tripTimer;
  double _drowsinessLevel = 15.0;

  @override
  void initState() {
    super.initState();
    _audio.init();
    _initCamera(0);
    _startTripTimer();
  }

  void _startTripTimer() {
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isMonitoring) {
        setState(() {
          _tripDurationSeconds++;
        });
      }
    });
  }

  String _formatTime(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _initCamera(int cameraIndex) async {
    await [Permission.camera, Permission.location, Permission.microphone].request();
    if (widget.cameras.isEmpty) return;

    if (cameraIndex >= widget.cameras.length) cameraIndex = 0;
    _selectedCameraIndex = cameraIndex;

    if (_cameraController != null) await _cameraController!.dispose();

    _cameraController = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      _cameraController!.startImageStream(_processImage);
      setState(() {});
    } catch (e) {
      print("Camera Error: $e");
    }
  }

  void _switchCamera() {
    if (widget.cameras.length < 2) return;
    _initCamera(_selectedCameraIndex + 1);
  }

  void _processImage(CameraImage image) async {
    if (_isProcessing || !_isMonitoring) return;
    _isProcessing = true;

    try {
      final inputImage = _convertInputImage(image);
      if (inputImage == null) {
        _isProcessing = false;
        return;
      }
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        String newStatus = _logic.checkFace(faces.first);
        if (newStatus != _status) _handleStatusChange(newStatus);
      }
    } catch (e) {
      print("Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _handleStatusChange(String newStatus) {
    setState(() {
      _status = newStatus;

      switch (newStatus) {
        case "AWAKE":
          _drowsinessLevel = 15;
          _audio.stopAll();
          _smsSent = false;
          break;
        case "DISTRACTED":
          _drowsinessLevel = 45;
          _triggerGemini("DISTRACTED");
          break;
        case "DROWSY":
          _drowsinessLevel = 75;
          _triggerGemini("DROWSY");
          break;
        case "ASLEEP":
          _drowsinessLevel = 95;
          _triggerSOS(); // Automatic trigger
          break;
      }
    });
  }

  void _triggerGemini(String state) async {
    if (DateTime.now().difference(_lastAiTrigger).inSeconds < 5) return;
    _lastAiTrigger = DateTime.now();
    String msg = await _gemini.getIntervention(state);
    setState(() => _aiMessage = msg);
    await _audio.speak(msg);
  }

  // --- AUTOMATIC SOS (When Asleep) ---
  void _triggerSOS() async {
    // 1. Play Alarm immediately
    await _audio.playAlarm();

    // 2. Send SMS immediately (Don't wait for AI)
    if (!_smsSent) {
      _smsSent = true;
      _smsService.sendEmergencyAlert();
    }

    // 3. Then get AI Voice
    String msg = await _gemini.getIntervention("ASLEEP");
    await _audio.speak(msg);
  }

  // --- MANUAL SOS (Button Press) ---
  void _manualEmergencyTrigger() {
    // Only send SMS directly. No sound, no waiting.
    _smsService.sendEmergencyAlert();

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Emergency Protocol Initiated..."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        )
    );
  }

  Color _getStatusColor() {
    if (_drowsinessLevel < 30) return Colors.green;
    if (_drowsinessLevel < 60) return Colors.amber;
    return Colors.red;
  }

  String _getStatusText() {
    if (_drowsinessLevel < 30) return "Alert";
    if (_drowsinessLevel < 60) return "Moderate";
    return "Drowsy";
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = _getStatusColor();
    double aspectRatio = 16 / 9;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      aspectRatio = _cameraController!.value.aspectRatio;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Yaqdah Dashboard", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_showCameraFeed ? Icons.videocam_off : Icons.videocam, color: Colors.white),
            onPressed: () => setState(() => _showCameraFeed = !_showCameraFeed),
            tooltip: "Toggle Camera View",
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.blueAccent),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Camera Feed
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Positioned(
              top: 0, left: 0, right: 0,
              height: _showCameraFeed ? 300 : 1,
              child: Opacity(
                opacity: _showCameraFeed ? 1.0 : 0.0,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width * aspectRatio,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 2. Dashboard
          Positioned.fill(
            top: _showCameraFeed ? 300 : 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Status Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Current Trip", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _isMonitoring ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _isMonitoring ? Colors.green : Colors.grey),
                              ),
                              child: Text(
                                _isMonitoring ? "Monitoring" : "Paused",
                                style: TextStyle(color: _isMonitoring ? Colors.green : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.remove_red_eye, color: statusColor, size: 20),
                                const SizedBox(width: 8),
                                Text("Status: ${_status}", style: const TextStyle(color: Colors.white)),
                              ],
                            ),
                            Text("${_drowsinessLevel.toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _drowsinessLevel / 100,
                            backgroundColor: Colors.grey[800],
                            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                            minHeight: 12,
                          ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.blue[700], borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.access_time, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Duration", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                      Text(_formatTime(_tripDurationSeconds), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.purple[700], borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.speed, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("AI Message", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                            _aiMessage,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_drowsinessLevel > 50)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Alert: $_status", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_aiMessage, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),

                  if (_drowsinessLevel > 50) const SizedBox(height: 16),

                  // Map Preview
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.map, size: 50, color: Colors.blue),
                              SizedBox(height: 8),
                              Text("Map View", style: TextStyle(color: Colors.white)),
                              Text("Current: Highway 15", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 16, left: 16,
                          child: _glassBadge(Icons.navigation, "To: Tripoli", Colors.blue),
                        ),
                        Positioned(
                          bottom: 16, right: 16,
                          child: _glassBadge(Icons.timer, "ETA: 2h 35m", Colors.white),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isMonitoring = !_isMonitoring),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: Colors.blue[700],
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Column(
                              children: [
                                Icon(_isMonitoring ? Icons.pause_circle_outline : Icons.play_circle_outline, color: Colors.white, size: 28),
                                const SizedBox(height: 8),
                                Text(_isMonitoring ? "Pause" : "Resume", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _manualEmergencyTrigger, // FIXED: Now calls the direct silent SMS function
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Colors.red, Colors.orange]),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                            ),
                            child: Column(
                              children: const [
                                Icon(Icons.emergency_share, color: Colors.white, size: 28),
                                SizedBox(height: 8),
                                Text("Emergency", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: _isListening ? Colors.red : Colors.blueAccent,
              onPressed: _toggleListening,
              child: Icon(_isListening ? Icons.mic_off : Icons.mic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  void _toggleListening() async {
    if (_isListening) {
      await _audio.stopListening();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _audio.listen((userText) async {
      if (!mounted) return;
      setState(() { _isListening = false; _aiMessage = "Analyzing..."; });
      String reply = await _gemini.chatWithDriver(userText);
      await _audio.speak(reply);
    });
  }

  InputImage? _convertInputImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) allBytes.putUint8List(plane.bytes);
    final bytes = allBytes.done().buffer.asUint8List();
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRotation = _rotationIntToImageRotation(_cameraController!.description.sensorOrientation);
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;
    return InputImage.fromBytes(bytes: bytes, metadata: InputImageMetadata(
      size: imageSize, rotation: imageRotation, format: inputImageFormat, bytesPerRow: image.planes[0].bytesPerRow,
    ));
  }

  InputImageRotation _rotationIntToImageRotation(int rotation) {
    switch (rotation) {
      case 90: return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default: return InputImageRotation.rotation0deg;
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    _audio.stopAll();
    _tripTimer?.cancel();
    super.dispose();
  }
}