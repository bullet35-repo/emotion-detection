import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:emotion_detection/features/emotion/presentation/pages/home_page.dart';

// Conditional imports — these files use dart:ffi (tflite_flutter) which
// doesn't exist on web. We only import them on mobile platforms.
import 'features/emotion/presentation/pages/livecamera_page.dart'
    if (dart.library.html) 'features/emotion/presentation/pages/web_stub.dart';
import 'features/emotion/presentation/pages/pick_image_page.dart'
    if (dart.library.html) 'features/emotion/presentation/pages/web_stub.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: "/",
      routes: {
        "/": (context) => const HomePage(),
        if (!kIsWeb) ...{
          "/live-camera": (context) => const LiveCameraPage(),
          "/pick-image": (context) => const PickImagePage(),
        },
      },
    );
  }
}
