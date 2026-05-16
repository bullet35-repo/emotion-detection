# Emotion Detection

A Flutter app for detecting facial emotions from a live camera feed or a selected image. The app uses Google ML Kit for face detection and a bundled TensorFlow Lite model for emotion classification.

## Features

- Live camera emotion detection with face tracking
- Image-based analysis from the gallery or camera
- TensorFlow Lite inference using the bundled model asset
- Google ML Kit face detection for locating faces before classification
- Confidence display and per-emotion probability breakdown
- Mobile-first flow with web guarded by a device-support message

## Detected Emotions

The bundled model currently includes these labels:

- Neutral
- Happy
- Surprise
- Sad
- Angry
- Disgust
- Fear
- Contempt

## Tech Stack

- Flutter and Dart
- `camera` for live camera frames
- `google_mlkit_face_detection` for face detection
- `tflite_flutter` for local model inference
- `image` for preprocessing and crop handling
- `image_picker` for gallery and camera image selection
- `permission_handler` for camera permission requests

## Project Structure

```text
assets/
  logo/                 App launcher/logo asset
  models/               TensorFlow Lite model and labels
lib/
  main.dart             App entry point and routes
  features/emotion/     Emotion detection pages, services, models, and utils
  widgets/              Shared UI widgets
test/                   Flutter widget tests
```

## Requirements

- Flutter SDK compatible with Dart `^3.10.8`
- Android Studio or Xcode for mobile builds
- A physical Android or iOS device is recommended for camera testing

## Getting Started

1. Install dependencies:

```bash
flutter pub get
```

2. Run the app on a connected mobile device or emulator:

```bash
flutter run
```

3. Run static analysis and tests:

```bash
flutter analyze
flutter test
```

## Model Assets

The app expects these assets to remain available and listed in `pubspec.yaml`:

- `assets/models/model_unquant.tflite`
- `assets/models/labels.txt`
- `assets/logo/logo.png`

If you replace the model, update `labels.txt` so the label order matches the model output order.

## Platform Notes

The app is designed for Android and iOS because the camera, ML Kit, and TensorFlow Lite pipeline depends on mobile platform capabilities. Web builds show a support message instead of loading the native inference pages.
