import 'package:emotion_detection/widgets/menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        body: Center(
          child: Text(
            'This app requires a mobile device.\nPlease run on Android or iOS.',
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion Detection'),
        centerTitle: true,
        backgroundColor: Colors.amber,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MenuButton(
              color: Colors.red,
              icon: Icons.videocam,
              title: 'Live Camera',
              subtitle: 'Detect emotion using camera + face detection',
              onTap: () => Navigator.pushNamed(context, '/live-camera'),
            ),
            const SizedBox(height: 20),
            MenuButton(
              color: Colors.green,
              icon: Icons.photo,
              title: 'Upload Image',
              subtitle: 'Pick an image and detect emotion',
              onTap: () => Navigator.pushNamed(context, '/pick-image'),
            ),
            const SizedBox(height: 28),
            const Text(
              'Tip: Start with Live Camera to verify the pipeline.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
