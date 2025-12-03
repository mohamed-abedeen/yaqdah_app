import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationSmsService {
  final String emergencyNumber = "1415";

  /// Get current GPS location
  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  /// Trigger the Emergency Protocol
  Future<void> sendEmergencyAlert() async {
    try {
      // A. Get Location
      Position? position = await _getCurrentLocation();
      String locationText = "Unknown Location";
      String mapsLink = "";

      if (position != null) {
        locationText = "${position.latitude}, ${position.longitude}";
        mapsLink = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
      }

      // B. Create Message
      String message = "EMERGENCY: The driver using Yaqdah has fallen asleep while driving! \n"
          "Location: $locationText \n"
          "Map: $mapsLink";

      // C. Send SMS
      // Use standard 'sms:' scheme which works on most devices
      final Uri smsLaunchUri = Uri(
        scheme: 'sms',
        path: emergencyNumber,
        queryParameters: <String, String>{
          'body': message,
        },
      );

      // Force external application launch
      if (await canLaunchUrl(smsLaunchUri)) {
        await launchUrl(smsLaunchUri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: Try launching without checking 'canLaunchUrl'
        // (Sometimes canLaunchUrl returns false on Android 11+ even if it works)
        try {
          await launchUrl(smsLaunchUri, mode: LaunchMode.externalApplication);
        } catch (e) {
          print("Could not launch SMS: $e");
        }
      }

    } catch (e) {
      print("Emergency Service Error: $e");
    }
  }
}