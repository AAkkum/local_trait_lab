# Local Trait Lab

Android-first Flutter prototype for local smartphone trait inference and model comparison. The current implementation focuses on emotion classification.

## Current State

Implemented:

- Single-image emotion analysis
- EmotiEff ONNX inference on Android
- Google ML Kit face detection and largest-face cropping before EmotiEff preprocessing
- Standardized seven-label output: `angry`, `disgust`, `fear`, `happy`, `neutral`, `sad`, `surprise`
- Benchmark mode for labeled image datasets
- Accuracy, macro-F1, per-class precision/recall/F1, confusion matrix, latency metrics
- CSV and JSON benchmark exports
- App-private model import so native ONNX Runtime can load model files reliably on Android
- Mock Gemma adapter and task-spec structure for later multimodal model integration

Not implemented yet:

- Real Gemma 4 runtime integration
- Persistent settings storage beyond the current in-memory prototype setup
- A polished model-management screen
- User-study questionnaire flow and backend upload of consented study data

## Model Setup

For EmotiEff:

1. Open `Advanced settings`.
2. Select `EmotiEff`.
3. Select a model variant, for example `EfficientNet B2 7-class`.
4. Set local runtime to `ONNX Runtime`.
5. Use `Import ONNX file` and select the matching `.onnx` model.

The app copies the selected model into private app storage. This is required because Android scoped storage can prevent native ONNX Runtime from reading files directly from shared folders such as `/sdcard/Download`.

Recommended first model:

```text
enet_b2_7.onnx
```

The 7-class model matches the app's current benchmark label space. 8-class EmotiEff models include `Contempt`, which is intentionally not mapped into the seven-label setup.

## Benchmark Dataset Format

The app imports benchmark datasets as a ZIP file or a folder with this structure:

```text
labels.csv
images/
  angry_001.png
  happy_001.png
```

`labels.csv`:

```csv
file,label
images/happy_001.png,happy
images/neutral_001.png,neutral
```

Supported labels:

```text
angry, disgust, fear, happy, neutral, sad, surprise
```

## FER2013 Conversion

A helper script creates a small app-ready benchmark ZIP from FER2013 CSV files or extracted class-folder datasets.

From a FER2013 CSV:

```bash
python3 tools/prepare_emotion_benchmark_dataset.py /path/to/fer2013.csv --split test --per-class 5 --output fer2013_test_35.zip
```

From an extracted folder dataset:

```bash
python3 tools/prepare_emotion_benchmark_dataset.py /path/to/extracted-fer2013 --split test --per-class 5 --output fer2013_test_35.zip
```

`--per-class 5` creates a 35-image benchmark sample. Increase this value for larger evaluations.

## Development Checks

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Run on a connected Android device:

```bash
flutter run -d <device-id>
```

## References

- EmotiEffLib / HSEmotion: https://github.com/sb-ai-lab/EmotiEffLib
- Google AI Edge Gallery: https://github.com/google-ai-edge/gallery
- FER2013 dataset: https://www.kaggle.com/datasets/msambare/fer2013
- FER2013 example repository: https://github.com/gitshanks/fer2013
