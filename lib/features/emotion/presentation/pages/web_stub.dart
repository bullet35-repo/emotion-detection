// Stub file for web platform.
// These classes are never instantiated on web — they just satisfy the compiler.
import 'package:flutter/material.dart';

class LiveCameraPage extends StatelessWidget {
  const LiveCameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Live Camera is not supported on the web.')),
    );
  }
}

class PickImagePage extends StatelessWidget {
  const PickImagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Image upload is not supported on the web.')),
    );
  }
}
