import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/tflite_emotion_service.dart';
import '../utils/emotion_utils.dart';
import '../utils/image_processing_utils.dart';
import '../widgets/confidence_bar.dart';

class LiveCameraPage extends StatefulWidget {
  const LiveCameraPage({super.key});

  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  CameraDescription? _activeCamera;
  List<CameraDescription> _cameras = [];

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
  );

  final TfliteEmotionService _emotionService = TfliteEmotionService();

  bool _isProcessing = false;
  DateTime _lastProcessed = DateTime.now();

  /// Minimum interval between processing frames (in milliseconds).
  /// Increase this value for smoother camera preview at the cost of
  /// slower emotion updates.
  static const int _frameIntervalMs = 500;

  String detectedEmotion = "Detecting...";
  double confidence = 0.0;

  // FER-Plus model specs: 48x48 grayscale, 1 channel, [0,1] normalization
  static const int inputSize = 48;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  /// Pause/resume camera stream based on app lifecycle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Stop the stream — camera is no longer visible
      if (controller.value.isStreamingImages) {
        controller.stopImageStream();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Restart the stream when the app comes back
      if (!controller.value.isStreamingImages) {
        controller.startImageStream(_processCameraImage);
      }
    }
  }

  Future<void> _initialize() async {
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        if (mounted) {
          setState(() {
            detectedEmotion = "Camera permission denied";
            confidence = 0.0;
          });
        }
        return;
      }

      await _emotionService.load();

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            detectedEmotion = "No camera available";
            confidence = 0.0;
          });
        }
        return;
      }

      // Default to the front (selfie) camera
      final cam = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _activeCamera = cam;

      await _startCamera(cam);
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) {
        setState(() {
          detectedEmotion = "Camera setup failed";
          confidence = 0.0;
        });
      }
    }
  }

  Future<void> _startCamera(CameraDescription cam) async {
    // Stop & dispose the old controller if any
    final old = _cameraController;
    if (old != null) {
      if (old.value.isStreamingImages) {
        await old.stopImageStream();
      }
      await old.dispose();
    }

    _activeCamera = cam;
    _cameraController = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    await _cameraController!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {
        detectedEmotion = "Align your face in the frame";
        confidence = 0.0;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    // Pick the other direction
    final currentDir = _activeCamera?.lensDirection;
    final newCam = _cameras.firstWhere(
      (c) => c.lensDirection != currentDir,
      orElse: () => _cameras.first,
    );

    try {
      await _startCamera(newCam);
    } catch (e) {
      debugPrint("Switch camera error: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessing || !_emotionService.isLoaded) return;

    // Throttle: skip frames that arrive too quickly
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < _frameIntervalMs) {
      return;
    }
    _lastProcessed = now;
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) {
        debugPrint(
          "[LiveCamera] inputImage is null — format: ${cameraImage.format.group}, planes: ${cameraImage.planes.length}",
        );
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            detectedEmotion = "No Face";
            confidence = 0.0;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          detectedEmotion = "Face detected, analyzing...";
          confidence = 0.0;
        });
      }

      // Pick biggest face
      final face = faces.reduce((a, b) {
        final areaA = a.boundingBox.width * a.boundingBox.height;
        final areaB = b.boundingBox.width * b.boundingBox.height;
        return areaA >= areaB ? a : b;
      });

      // Convert camera frame to RGB image
      final rgbImage = ImageProcessingUtils.convertCameraImageToImage(
        cameraImage,
      );
      if (rgbImage == null) {
        if (mounted) {
          setState(() {
            detectedEmotion = "Unsupported camera frame";
            confidence = 0.0;
          });
        }
        return;
      }

      // Rotate the RGB image to match ML Kit's coordinate space.
      // ML Kit returns face bounding boxes in the rotated image space,
      // but _convertCameraImageToImage gives us raw/unrotated pixels.
      var rotatedImage = ImageProcessingUtils.rotateImage(
        rgbImage,
        _getRotationDegrees(),
      );

      // Flip horizontally for front camera.
      // Teachable Machine records training data from the mirrored front-camera
      // preview, so we need to mirror our input to match that orientation.
      if (_activeCamera?.lensDirection == CameraLensDirection.front) {
        rotatedImage = ImageProcessingUtils.flipHorizontal(rotatedImage);
      }

      // Crop face region (with padding for better accuracy)
      final cropped = ImageProcessingUtils.cropToFace(
        rotatedImage,
        face.boundingBox,
      );
      if (cropped == null) {
        return;
      }

      // Preprocess to Float32List (224x224x3)
      final inputTensor = ImageProcessingUtils.preprocessToFloat32(
        cropped,
        inputSize,
      );

      // Run model and get probabilities
      final probs = _emotionService.runInference(inputTensor);

      // Find best label + confidence
      var bestIdx = 0;
      for (var i = 1; i < probs.length; i++) {
        if (probs[i] > probs[bestIdx]) bestIdx = i;
      }

      final label = _emotionService.labels[bestIdx];
      final conf = probs[bestIdx];

      if (mounted) {
        setState(() {
          detectedEmotion = label;
          confidence = conf;
        });
      }
    } catch (e) {
      debugPrint("Live camera error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _activeCamera;
    if (camera == null) {
      debugPrint("[LiveCamera] _activeCamera is null");
      return null;
    }

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_cameraController?.value.deviceOrientation];
      if (rotationCompensation == null) {
        debugPrint("[LiveCamera] rotationCompensation is null");
        return null;
      }
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) {
      debugPrint("[LiveCamera] rotation is null");
      return null;
    }

    // Determine the image format for ML Kit
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    debugPrint(
      "[LiveCamera] format.raw=${image.format.raw}, resolved=$format, planes=${image.planes.length}",
    );

    if (Platform.isAndroid) {
      // On Android, ML Kit requires NV21 format.
      // Some devices deliver NV21 (1 plane), others deliver YUV420 (3 planes).
      Uint8List bytes;
      int bytesPerRow;

      if (image.planes.length == 1) {
        // True NV21 — single interleaved plane
        bytes = image.planes.first.bytes;
        bytesPerRow = image.planes.first.bytesPerRow;
      } else if (image.planes.length >= 3) {
        // YUV420 (3 separate planes) — concatenate into NV21-compatible buffer
        bytes = ImageProcessingUtils.yuv420ToNv21(image);
        bytesPerRow = image.planes.first.bytesPerRow;
      } else {
        debugPrint(
          "[LiveCamera] Unsupported plane count: ${image.planes.length}",
        );
        return null;
      }

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } else if (Platform.isIOS) {
      if (format != InputImageFormat.bgra8888) {
        debugPrint("[LiveCamera] iOS format is not bgra8888: $format");
        return null;
      }
      if (image.planes.isEmpty) return null;
      final plane = image.planes.first;

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      );

      return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
    }

    return null;
  }

  /// Returns the rotation degrees that ML Kit uses for the InputImage.
  /// We need to rotate our RGB image by the same amount so that the face
  /// bounding box coordinates align with the pixel data.
  int _getRotationDegrees() {
    final camera = _activeCamera;
    if (camera == null) return 0;

    final sensorOrientation = camera.sensorOrientation;

    if (Platform.isIOS) {
      return sensorOrientation;
    }

    // Android: same calculation as in _inputImageFromCameraImage
    var rotationCompensation =
        _orientations[_cameraController?.value.deviceOrientation] ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    return rotationCompensation;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      unawaited(controller.stopImageStream());
    }
    controller?.dispose();
    _faceDetector.close();
    _emotionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final color = EmotionUtils.color(detectedEmotion);
    final labels = _emotionService.labels;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Live Emotion Detection",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        actions: [
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch_rounded),
              tooltip: 'Switch Camera',
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: Column(
        children: [
          Flexible(flex: 3, child: CameraPreview(_cameraController!)),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emotion icon + label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          EmotionUtils.icon(detectedEmotion),
                          color: color,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          detectedEmotion,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Confidence bar
                    ConfidenceBar(value: confidence, color: color),

                    // All-emotion icon row
                    if (labels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(labels.length, (i) {
                          final isActive = labels[i] == detectedEmotion;
                          final c = EmotionUtils.color(labels[i]);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                EmotionUtils.icon(labels[i]),
                                color: isActive ? c : Colors.grey.shade300,
                                size: 18,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: isActive
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isActive ? c : Colors.grey.shade400,
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
