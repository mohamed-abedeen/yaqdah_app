import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/home_screen.dart'; // Point to the new file

Future<void> main() async {
  // 1. Initialize Flutter Bindings
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Cameras with Safety Check
  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    // This print will show up in your Debug Console if the app crashes here
    print("CRITICAL CAMERA ERROR: $e");
  }

  // 3. Run the App
  runApp(YaqdahApp(cameras: cameras));
}

class YaqdahApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const YaqdahApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Yaqdah',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.cyan,
      ),
      // Safety Check: If no cameras were found, show an error screen instead of crashing
      home: cameras.isEmpty
          ? const Scaffold(
              body: Center(
                child: Text(
                  "No Camera Found\nCheck permissions or device.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            )
          : HomeScreen(cameras: cameras),
    );
  }
}
