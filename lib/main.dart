import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hud_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape HUD, fullscreen.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ObdHudApp());
}

class ObdHudApp extends StatelessWidget {
  const ObdHudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'ExCar',
      debugShowCheckedModeBanner: false,
      home: HudScreen(),
    );
  }
}
