import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../data/models/face_result.dart';
import '../../data/services/tflite_emotion_service.dart';
import '../utils/emotion_utils.dart';
import '../widgets/confidence_bar.dart';
import '../../../../widgets/action_button.dart';

class PickImagePage extends StatefulWidget {
  const PickImagePage({super.key});

  @override
  State<PickImagePage> createState() => _PickImagePageState();
}

class _PickImagePageState extends State<PickImagePage> {
  final ImagePicker _picker = ImagePicker();
  final TfliteEmotionService _emotionService = TfliteEmotionService();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate),
  );

  File? _imageFile;
  bool _isAnalyzing = false;
  String _statusMessage = 'Pick an image to detect emotion';
  List<FaceResult> _faceResults = [];

  @override
  void initState() {
    super.initState();
    _emotionService.load().catchError((e) {
      debugPrint('EmotionService load error: $e');
    });
  }

  @override
  void dispose() {
    _faceDetector.close();
    _emotionService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1280,
    );
    if (picked == null) return;

    setState(() {
      _imageFile = File(picked.path);
      _faceResults = [];
      _statusMessage = 'Analyzing...';
      _isAnalyzing = true;
    });

    await _analyzeImage(_imageFile!);
  }

  Future<void> _analyzeImage(File file) async {
    try {
      // Detect faces using ML Kit
      final inputImage = InputImage.fromFile(file);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() {
          _statusMessage = 'No face detected in the image.';
          _isAnalyzing = false;
          _faceResults = [];
        });
        return;
      }

      // Decode and bake EXIF orientation into pixels.
      // ML Kit reads EXIF and gives bounding boxes in the corrected space.
      // Without bakeOrientation(), we crop the wrong region and get bad results.
      final bytes = await file.readAsBytes();
      final rawDecoded = img.decodeImage(bytes);
      if (rawDecoded == null) {
        setState(() {
          _statusMessage = 'Could not decode image.';
          _isAnalyzing = false;
        });
        return;
      }
      // Apply EXIF rotation so pixel coordinates match ML Kit bounding boxes
      final decoded = img.bakeOrientation(rawDecoded);

      debugPrint(
        '[PickImage] Image size after bake: ${decoded.width}x${decoded.height}',
      );
      debugPrint('[PickImage] Faces found: ${faces.length}');
      for (final f in faces) {
        debugPrint('[PickImage] Face bbox: ${f.boundingBox}');
      }

      // Analyze each face
      final results = <FaceResult>[];
      for (final face in faces) {
        final cropped = _cropFace(decoded, face.boundingBox);
        if (cropped == null) {
          debugPrint(
            '[PickImage] Crop returned null for bbox ${face.boundingBox}',
          );
          continue;
        }

        debugPrint(
          '[PickImage] Cropped face size: ${cropped.width}x${cropped.height}',
        );

        // For static images, use direct 4D nested list — most reliable approach
        // (speed doesn't matter here, we only run inference once)
        final probs = _runInferenceOnFace(cropped);

        debugPrint('[PickImage] Raw probs: $probs');

        var bestIdx = 0;
        for (var i = 1; i < probs.length; i++) {
          if (probs[i] > probs[bestIdx]) bestIdx = i;
        }

        final label = _emotionService.labels.isNotEmpty
            ? _emotionService.labels[bestIdx]
            : 'Unknown';
        final conf = probs[bestIdx];

        results.add(
          FaceResult(
            boundingBox: face.boundingBox,
            emotion: label,
            confidence: conf,
            allProbs: List<double>.from(probs),
          ),
        );
      }

      // Show the highest-confidence result as the main result
      results.sort((a, b) => b.confidence.compareTo(a.confidence));

      setState(() {
        _faceResults = results;
        _statusMessage = results.length == 1
            ? '1 face detected'
            : '${results.length} faces detected';
        _isAnalyzing = false;
      });
    } catch (e) {
      debugPrint('PickImage analysis error: $e');
      setState(() {
        _statusMessage = 'Analysis failed: $e';
        _isAnalyzing = false;
      });
    }
  }

  /// Crops the face region as a square with padding.
  /// Square crops match how Teachable Machine trains (224×224).
  img.Image? _cropFace(img.Image src, Rect bbox, {double padFactor = 0.3}) {
    // Expand to square — use the larger dimension
    final cx = bbox.center.dx;
    final cy = bbox.center.dy;
    final halfSide = math.max(bbox.width, bbox.height) / 2 * (1 + padFactor);

    final left = (cx - halfSide).floor().clamp(0, src.width - 1);
    final top = (cy - halfSide).floor().clamp(0, src.height - 1);
    final right = (cx + halfSide).ceil().clamp(0, src.width);
    final bottom = (cy + halfSide).ceil().clamp(0, src.height);

    final w = math.max(1, right - left);
    final h = math.max(1, bottom - top);
    if (w <= 1 || h <= 1) return null;

    return img.copyCrop(src, x: left, y: top, width: w, height: h);
  }

  /// Normalizes image brightness/contrast for more consistent model input.
  img.Image _normalizeImage(img.Image src) {
    // Adjust contrast slightly — helps with dark or washed out photos
    return img.adjustColor(src, contrast: 1.2);
  }

  /// Runs inference on a single face crop.
  /// FER-Plus model expects [1, 48, 48, 1] grayscale input normalized to [0,1].
  List<double> _runSingleInference(img.Image face) {
    const size = 48;
    final normalized = _normalizeImage(face);
    final resized = img.copyResize(normalized, width: size, height: size);

    // Build [1][48][48][1] — single grayscale channel
    final input4d = List.generate(
      1,
      (_) => List.generate(
        size,
        (y) => List.generate(size, (x) {
          final p = resized.getPixel(x, y);
          // Convert to grayscale and normalize to [0, 1]
          final gray =
              (0.299 * p.r.toDouble() +
                  0.587 * p.g.toDouble() +
                  0.114 * p.b.toDouble()) /
              255.0;
          return [gray]; // 1 channel, not 3
        }),
      ),
    );

    final outputCount = _emotionService.outputShape.isNotEmpty
        ? _emotionService.outputShape.last
        : _emotionService.labels.length;

    final outputBuffer = [List<double>.filled(outputCount, 0.0)];
    _emotionService.run(input4d, outputBuffer);

    return outputBuffer[0];
  }

  /// Multi-crop ensemble: runs inference on 3 slightly different crops
  /// and averages the probabilities for a more stable result.
  List<double> _runInferenceOnFace(img.Image face) {
    // Crop 1: original (padFactor already applied in _cropFace)
    final probs1 = _runSingleInference(face);

    // Crop 2: slightly tighter (center 85% of the image)
    final tighter = _centerCrop(face, 0.85);
    final probs2 = _runSingleInference(tighter);

    // Crop 3: horizontally flipped (helps with asymmetric training data)
    final flipped = img.flipHorizontal(img.Image.from(face));
    final probs3 = _runSingleInference(flipped);

    // Average the three runs
    final count = probs1.length;
    final averaged = List<double>.generate(count, (i) {
      return (probs1[i] + probs2[i] + probs3[i]) / 3.0;
    });

    debugPrint(
      '[PickImage] Ensemble: orig=$probs1, tight=$probs2, flip=$probs3',
    );
    debugPrint('[PickImage] Averaged: $averaged');

    return averaged;
  }

  /// Returns the center portion of an image (e.g. fraction=0.85 keeps 85%).
  img.Image _centerCrop(img.Image src, double fraction) {
    final cw = (src.width * fraction).round();
    final ch = (src.height * fraction).round();
    final dx = (src.width - cw) ~/ 2;
    final dy = (src.height - ch) ~/ 2;
    return img.copyCrop(src, x: dx, y: dy, width: cw, height: ch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Upload Image',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Image preview area
          Expanded(
            child: _imageFile == null
                ? _buildEmptyState()
                : _buildImagePreview(),
          ),

          // Results panel
          if (_imageFile != null) _buildResultsPanel(),

          // Bottom action buttons
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12, width: 2),
            ),
            child: const Icon(
              Icons.add_photo_alternate_outlined,
              size: 56,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No image selected',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick a photo from gallery or take one\nwith the camera',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_imageFile!, fit: BoxFit.contain),
        if (_isAnalyzing)
          Container(
            color: Colors.black45,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Detecting faces...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultsPanel() {
    if (_isAnalyzing) return const SizedBox.shrink();

    if (_faceResults.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: const Color(0xFF1A1A2E),
        child: Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 15),
        ),
      );
    }

    return Container(
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _faceResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final r = _faceResults[index];
                final color = EmotionUtils.color(r.emotion);
                return Container(
                  width: 160,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            EmotionUtils.icon(r.emotion),
                            color: color,
                            size: 22,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Face ${index + 1}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        r.emotion,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ConfidenceBar(
                        value: r.confidence,
                        color: color,
                        backgroundColor: Colors.white12,
                        textColor: color.withOpacity(0.8),
                        borderRadius: 4,
                        barHeight: 6,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // All probabilities for the top face
          if (_faceResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildProbabilityBreakdown(_faceResults.first),
          ],
        ],
      ),
    );
  }

  Widget _buildProbabilityBreakdown(FaceResult result) {
    final labels = _emotionService.labels;
    if (labels.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All emotions:',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            math.min(labels.length, result.allProbs.length),
            (i) {
              final label = labels[i];
              final prob = result.allProbs[i];
              final color = EmotionUtils.color(label);
              final isTop = label == result.emotion;
              return Column(
                children: [
                  Text(
                    '${(prob * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: isTop ? color : Colors.white38,
                      fontSize: 11,
                      fontWeight: isTop ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: isTop ? color : Colors.white30,
                      fontSize: 10,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF12122A),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ActionButton(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              color: const Color(0xFF4CAF50),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ActionButton(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              color: const Color(0xFF2196F3),
              onTap: () => _pickImage(ImageSource.camera),
            ),
          ),
        ],
      ),
    );
  }
}
