import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_iot/wifi_iot.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Connect App',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const WiFiHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WiFiHomePage extends StatefulWidget {
  const WiFiHomePage({super.key});

  @override
  State<WiFiHomePage> createState() => _WiFiHomePageState();
}

class _WiFiHomePageState extends State<WiFiHomePage> {
  // Your WiFi hotspots with Dubai coordinates and others for test
  final List<Map<String, dynamic>> wifiDatabase = [
    {
      "ssid": "Dubai_Cafe_WiFi",
      "password_encrypted": base64.encode(utf8.encode("dubai1234")),
      "location": {"latitude": 25.334000, "longitude": 55.392000}
    },
    // You can add more known networks here...
  ];

  List<Map<String, dynamic>> nearbyNetworks = [];
  bool _isLoading = false;

  Future<bool> _checkLocationPermission() async {
    var status = await Permission.location.status;
    if (status.isGranted) return true;

    var result = await Permission.location.request();
    return result.isGranted;
  }

  Future<Position?> _getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Fluttertoast.showToast(msg: "Location services are disabled.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Fluttertoast.showToast(msg: "Location permission denied.");
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        Fluttertoast.showToast(msg: "Location permission denied forever. Please enable it from settings.");
        return null;
      }

      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      Fluttertoast.showToast(msg: "Error getting location: $e");
      return null;
    }
  }

  Future<void> scanAndDisplay() async {
    setState(() {
      _isLoading = true;
      nearbyNetworks = [];
    });

    bool permissionGranted = await _checkLocationPermission();
    if (!permissionGranted) {
      setState(() => _isLoading = false);
      return;
    }

    final Position? pos = await _getCurrentPosition();
    if (pos == null) {
      setState(() => _isLoading = false);
      return;
    }

    if (Platform.isAndroid) {
      // Android: try WiFi scan first (if available)
      List<WifiNetwork?>? scannedNetworks = await WiFiForIoTPlugin.loadWifiList();
      if (scannedNetworks == null || scannedNetworks.isEmpty) {
        Fluttertoast.showToast(msg: "No WiFi networks detected by scanner, falling back to location.");
        // fallback to location filtering below
      } else {
        List<Map<String, dynamic>> matched = [];
        for (var scanned in scannedNetworks) {
          var match = wifiDatabase.firstWhere(
            (db) => db['ssid'] == scanned?.ssid,
            orElse: () => {},
          );
          if (match.isNotEmpty) matched.add(match);
        }
        setState(() {
          nearbyNetworks = matched;
          _isLoading = false;
        });
        return;
      }
    }

    // iOS or fallback: Filter WiFi networks from DB by proximity to GPS position
    const double radiusMeters = 50; // ~50 meters
    List<Map<String, dynamic>> matched = wifiDatabase.where((wifi) {
      double lat = wifi["location"]["latitude"];
      double lon = wifi["location"]["longitude"];
      double distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        lat,
        lon,
      );
      return distance <= radiusMeters;
    }).toList();

    setState(() {
      nearbyNetworks = matched;
      _isLoading = false;
    });
  }

  String decodePassword(String encrypted) {
    try {
      return utf8.decode(base64.decode(encrypted));
    } catch (_) {
      return "Invalid password encoding";
    }
  }

  void connectToNetwork(Map<String, dynamic> wifi) async {
    String ssid = wifi["ssid"];
    String password = decodePassword(wifi["password_encrypted"]);

    if (Platform.isAndroid) {
      bool connected = await WiFiForIoTPlugin.connect(
        ssid,
        password: password,
        security: NetworkSecurity.WPA,
        joinOnce: true,
      );
      Fluttertoast.showToast(
        msg: connected ? "Connected to $ssid" : "Failed to connect.",
      );
    } else {
      // iOS: manual connect with credentials shown
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("Manual Connect"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText("SSID: $ssid"),
              SelectableText("Password: $password"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("WiFi Connect App")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _isLoading ? null : scanAndDisplay,
              icon: const Icon(Icons.wifi),
              label: Text(_isLoading ? "Scanning..." : "Scan & Connect to WiFi"),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : nearbyNetworks.isEmpty
                      ? const Center(
                          child: Text(
                            "No nearby WiFi networks found within 50 meters.",
                            style: TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: nearbyNetworks.length,
                          itemBuilder: (context, index) {
                            final wifi = nearbyNetworks[index];
                            return Card(
                              child: ListTile(
                                title: Text(wifi["ssid"]),
                                subtitle: const Text("Tap to see/connect"),
                                trailing: const Icon(Icons.wifi),
                                onTap: () => connectToNetwork(wifi),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

