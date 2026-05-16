import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../data/services/tflite_emotion_service.dart';
import '../../data/services/model_inspector.dart';

class ModelDebugPage extends StatefulWidget {
  const ModelDebugPage({super.key});

  @override
  State<ModelDebugPage> createState() => _ModelDebugPageState();
}

class _ModelDebugPageState extends State<ModelDebugPage> {
  final svc = TfliteEmotionService();

  String status = 'Loading...';
  Map<String, dynamic>? details;
  String labelsPreview = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await svc.load();

      // Create a temp interpreter just to read tensors (svc already has one, but we didn't expose it).
      // So we load another interpreter quickly for inspection:
      final inspectorInterpreter = await Interpreter.fromAsset(
        'assets/models/model_unquant.tflite',
      );
      final d = ModelInspector.describe(inspectorInterpreter);
      inspectorInterpreter.close();

      setState(() {
        status = 'Loaded ✅';
        details = d;
        labelsPreview = svc.labels.take(10).join(', ');
      });
    } catch (e) {
      setState(() => status = 'Error: $e');
    }
  }

  @override
  void dispose() {
    svc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = details;

    return Scaffold(
      appBar: AppBar(title: const Text('Model Debug')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(status, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 16),

            if (d != null) ...[
              const Text(
                'Input Tensor',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text('Name: ${d['input']['name']}'),
              Text('Shape: ${d['input']['shape']}'),
              Text('Type: ${d['input']['type']}'),
              const SizedBox(height: 16),

              const Text(
                'Output Tensor',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text('Name: ${d['output']['name']}'),
              Text('Shape: ${d['output']['shape']}'),
              Text('Type: ${d['output']['type']}'),
              const SizedBox(height: 16),

              const Text(
                'Labels (first 10)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(labelsPreview.isEmpty ? '(none)' : labelsPreview),
            ],
          ],
        ),
      ),
    );
  }
}
