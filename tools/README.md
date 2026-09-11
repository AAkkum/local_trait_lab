# Tools

This folder contains offline Python utilities used to prepare research and benchmark material for Local Trait Lab. These scripts are not part of the Flutter app runtime.

## Benchmark Dataset Preparation

`prepare_emotion_benchmark_dataset.py` converts an AffectNet-style class-folder dataset into the format expected by the Android benchmark screen.

Input layout:

```text
affectnet/
  anger/
  disgust/
  fear/
  happy/
  neutral/
  sad/
  surprise/
```

Command:

```bash
python3 tools/prepare_emotion_benchmark_dataset.py /path/to/affectnet --output tools/affectnet7_100 --per-class 100 --overwrite
```

Output layout:

```text
affectnet7_100/
  labels.csv
  images/
```

The script maps `anger` to `angry` and excludes `contempt` because the current app benchmark uses seven emotion labels.

## Why This Is Separate From the App

Dataset sampling and model-conversion experiments should be reproducible, but they should not be mixed into the Flutter application code. Keeping them here makes it clear which parts are app runtime code and which parts are research preparation scripts.

## Benchmark Export Summaries

`summarize_benchmark_exports.py` scans app-exported `*_summary.json` files and creates a compact model-comparison report.

Command:

```bash
python3 tools/summarize_benchmark_exports.py exports
```

Outputs:

```text
exports/model_comparison_report.md
exports/model_comparison_report.csv
```

The report is useful for comparing model accuracy, macro-F1, per-class F1, and latency across benchmark runs without rerunning inference on the phone.
