# Android integration notes

This prototype is Android-first, but the current environment does not have Flutter or Android tooling installed.

## TODO integration points

- Gemma runtime hookup for LiteRT / Google AI Edge style multimodal execution
- EmotiEff / HSEmotion runtime hookup for ONNX Runtime or native Android inference
- Storage Access Framework specific polishing for large datasets
- Background execution hardening for long benchmark runs

The Dart-side app already routes everything through `AnalysisModel` and runtime selection in `ModelConfig`.
