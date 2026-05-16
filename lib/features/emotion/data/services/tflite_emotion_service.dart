import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TfliteEmotionService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  List<int> _inputShape = [];
  List<int> _outputShape = [];

  bool get isLoaded => _interpreter != null && _labels.isNotEmpty;
  List<String> get labels => _labels;
  List<int> get inputShape => _inputShape;
  List<int> get outputShape => _outputShape;

  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/models/model_unquant.tflite',
      options: InterpreterOptions()..threads = 4,
    );

    // Log model tensor info for debugging
    final inTensor = _interpreter!.getInputTensors().first;
    final outTensor = _interpreter!.getOutputTensors().first;
    _inputShape = inTensor.shape;
    _outputShape = outTensor.shape;

    debugPrint(
      '[EmotionService] Input  tensor: shape=${inTensor.shape}, type=${inTensor.type}',
    );
    debugPrint(
      '[EmotionService] Output tensor: shape=${outTensor.shape}, type=${outTensor.type}',
    );

    final labelsRaw = await rootBundle.loadString('assets/models/labels.txt');
    _labels = labelsRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => e.replaceFirst(RegExp(r'^\d+\s*'), ''))
        .toList();

    debugPrint('[EmotionService] Labels (${_labels.length}): $_labels');
  }

  /// Runs inference and returns the output probabilities as List<double>.
  /// [input] should be a Float32List with (height * width * channels) elements.
  List<double> runInference(Float32List input) {
    final interpreter = _interpreter;
    if (interpreter == null) throw StateError('Interpreter not loaded');

    // Use tflite_flutter's .reshape() extension to efficiently convert
    // the flat Float32List into the 4D shape the model expects [1, 224, 224, 3].
    // This is much faster than List.generate and works reliably unlike ByteBuffer.
    final shaped = input.reshape(_inputShape);

    final outputCount = _outputShape.last;
    final outputBuffer = [List<double>.filled(outputCount, 0.0)];

    interpreter.run(shaped, outputBuffer);

    return outputBuffer[0];
  }

  /// Generic runner (legacy).
  void run(Object input, Object output) {
    final interpreter = _interpreter;
    if (interpreter == null) throw StateError('Interpreter not loaded');
    interpreter.run(input, output);
  }

  /// Convenience: get the top label given probabilities
  String argmaxLabel(List<double> probs) {
    if (_labels.isEmpty) return 'No labels';
    var bestIdx = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) bestIdx = i;
    }
    return _labels[bestIdx];
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
