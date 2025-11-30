import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logic/drowsiness_logic.dart';
import '../services/gemini_service.dart';
import '../services/audio_service.dart';
import '../services/location_sms_service.dart'; // NEW IMPORT
import '../widgets/status_panel.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
  final LocationSmsService _smsService = LocationSmsService(); // NEW SERVICE

  bool _isProcessing = false;
  String _status = "INITIALIZING";
  String _aiMessage = "النظام يعمل";
  Color _statusColor = Colors.cyan;
  DateTime _lastAiTrigger = DateTime.now();

  // Prevent sending multiple SMS in one sleep session
  bool _smsSent = false;

  @override
  void initState() {
    super.initState();
    _audio.init();
    _initCamera(0);
  }

  Future<void> _initCamera(int cameraIndex) async {
    // Request permissions (Camera + Location)
    await [Permission.camera, Permission.location, Permission.sms].request();

    if (widget.cameras.isEmpty) return;

    if (cameraIndex >= widget.cameras.length) cameraIndex = 0;
    _selectedCameraIndex = cameraIndex;

    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      widget.cameras[cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      _cameraController!.startImageStream(_processImage);
      setState(() {});
    } catch (e) {
      print("Camera connection error: $e");
    }
  }

  void _switchCamera() {
    if (widget.cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No other cameras found!"))
      );
      return;
    }

    int newIndex = _selectedCameraIndex + 1;
    _initCamera(newIndex);
  }

  void _processImage(CameraImage image) async {
    if (_isProcessing) return;
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

      if (newStatus == "AWAKE") {
        _statusColor = Colors.cyan;
        _audio.stopAll();
        _smsSent = false; // Reset SMS flag so we can send again next time
      } else if (newStatus == "DISTRACTED") {
        _statusColor = Colors.yellow;
        _triggerGemini("DISTRACTED");
      } else if (newStatus == "DROWSY") {
        _statusColor = Colors.orange;
        _triggerGemini("DROWSY");
      } else if (newStatus == "ASLEEP") {
        _statusColor = Colors.red;
        _triggerSOS();
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

  void _triggerSOS() async {
    setState(() => _aiMessage = "🚨 استيقظ! خطر!");

    // 1. Play Alarm
    await _audio.playAlarm();

    // 2. Speak Prompt
    String msg = await _gemini.getIntervention("ASLEEP");
    await _audio.speak(msg);

    // 3. Send SMS (Only once per sleep event)
    if (!_smsSent) {
      _smsSent = true;
      print("Sending Emergency SMS...");
      _smsService.sendEmergencyAlert();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Yaqdah Test Mode", style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.cameraswitch, color: Colors.cyan),
            onPressed: _switchCamera,
            tooltip: "Switch Camera",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _statusColor, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: CameraPreview(_cameraController!),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: StatusPanel(
              status: _status,
              message: _aiMessage,
              color: _statusColor,
              onStopAlarm: () {
                _audio.stopAll();
                setState(() {
                  _status = "AWAKE";
                  _statusColor = Colors.cyan;
                  _aiMessage = "توقف التنبيه";
                  _smsSent = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  InputImage? _convertInputImage(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final imageRotation = _rotationIntToImageRotation(_cameraController!.description.sensorOrientation);
    final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
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
    super.dispose();
  }
}