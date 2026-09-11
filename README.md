# Local Trait Lab

Local Trait Lab is an Android-first Flutter research prototype for studying local AI-based privacy inferences on smartphones. The app lets participants select personal images or PDF files, analyzes them locally with an on-device model, shows inferred personal signals, and records participant reactions for later research evaluation.

The project was built for a bachelor thesis at TU Darmstadt / PEASEC. It is not a production app and is not intended for app-store deployment.

## Current Capabilities

- Android-first Flutter app with a complete study flow.
- In-app information sheet and consent checkboxes.
- Baseline questionnaire screens for demographics, privacy attitudes, and technology affinity.
- Local Gemma 4 E2B model download into private app storage.
- Local image and first-page PDF analysis using Gemma task specifications.
- Combined profile synthesis from multiple file-level inferences.
- Per-inference and final study questions.
- Front-camera emotion-label sampling during study stages. Camera frames are processed locally and are not stored.
- Export of a pseudonymized study run as JSON.
- Separate model benchmark workflow for emotion classification.
- Android ONNX Runtime integration for EmotiEff/HSEmotion-style emotion models.
- Benchmark metrics: accuracy, macro-F1, per-class precision/recall/F1, confusion matrix, and latency.

## Project Structure

```text
lib/
  analysis/                 shared model interfaces, requests, results, task specs
  app/                      app controller and high-level state
  benchmark/                dataset loading, benchmark runner, metrics, exports
  features/                 Flutter screens and study UI
  models/                   Gemma and EmotiEff adapters
  platform/android/         Android-specific PDF rendering and runtime bridges
assets/gemma_tasks/         JSON task specifications for Gemma prompts and output schemas
tools/                      Python utilities for preparing benchmark data
ResEmoteNet/                local conversion/validation workspace for ResEmoteNet experiments
```

## Why `tools/` Exists

The Flutter app should stay focused on participant interaction and on-device inference. The `tools/` folder is for reproducible offline preparation work that does not belong inside the app runtime.

Current example: `tools/prepare_emotion_benchmark_dataset.py` creates app-compatible benchmark folders from an AffectNet-style class-folder dataset. This keeps dataset sampling explicit and repeatable instead of manually copying files.

For job applications, this folder is the right place to show Python work because it demonstrates reproducible data preparation and evaluation support around the app. The current reporting script reads exported benchmark JSON files and creates comparison tables with accuracy, macro-F1, latency, and per-class F1 values.

## Model Artifacts

Large model files are intentionally not included in the repository.

- Gemma 4 E2B is downloaded by the app into private Android app storage.
- EmotiEff/ONNX models must be imported through the app settings or prepared locally.
- ResEmoteNet `.pth`, generated `.onnx`, virtual environments, and downloaded benchmark datasets are ignored by Git.

## Privacy Study Flow

1. Participant reads the information sheet and gives consent in the app.
2. Participant answers baseline questions.
3. The app prepares the local Gemma model if it is not already installed.
4. Participant selects images or PDFs.
5. Each selected file is analyzed locally on the phone.
6. Participant rates the shown inferences.
7. The app generates a combined profile from the file-level results.
8. Participant answers final questions.
9. The study run can be exported as JSON for research evaluation.

Raw selected files and camera frames are not exported by the app. The exported study data contains consent decisions, questionnaire answers, generated model outputs, ratings, technical metadata, and derived front-camera emotion labels/confidence values.

## Emotion Benchmark Workflow

The benchmark workflow is separate from the participant study flow. It is used to compare emotion-classification backends on labeled datasets.

Expected dataset format:

```text
labels.csv
images/
  angry_00001.jpg
  happy_00001.jpg
```

`labels.csv` format:

```csv
file,label
images/happy_00001.jpg,happy
images/neutral_00001.jpg,neutral
```

Supported labels:

```text
angry, disgust, fear, happy, neutral, sad, surprise
```

## Preparing AffectNet-Style Benchmarks

Example:

```bash
python3 tools/prepare_emotion_benchmark_dataset.py /path/to/affectnet --output tools/affectnet7_100 --per-class 100 --overwrite
```

The script expects class folders such as `anger`, `disgust`, `fear`, `happy`, `neutral`, `sad`, and `surprise`. The AffectNet folder name `anger` is mapped to the app label `angry`. The `contempt` class is excluded for the seven-label setup.

## Summarizing Benchmark Exports

After exporting benchmark summaries from the app, generate a comparison report with:

```bash
python3 tools/summarize_benchmark_exports.py exports
```

This writes:

```text
exports/model_comparison_report.md
exports/model_comparison_report.csv
```

The report ranks models by accuracy and macro-F1, includes latency, and shows per-class F1 values. It does not rerun inference; it only summarizes exported benchmark files.

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
- Gemma local model format via Google AI Edge / LiteRT-LM
- AffectNet dataset family for facial emotion benchmarks
- ResEmoteNet experiments used for comparison during development
