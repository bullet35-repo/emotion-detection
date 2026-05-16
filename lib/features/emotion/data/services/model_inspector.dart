import 'package:tflite_flutter/tflite_flutter.dart';

class ModelInspector {
  static Map<String, dynamic> describe(Interpreter interpreter) {
    final inTensor = interpreter.getInputTensors().first;
    final outTensor = interpreter.getOutputTensors().first;

    return {
      'input': {
        'shape': inTensor.shape,
        'type': inTensor.type.toString(),
        'name': inTensor.name,
      },
      'output': {
        'shape': outTensor.shape,
        'type': outTensor.type.toString(),
        'name': outTensor.name,
      },
    };
  }
}
