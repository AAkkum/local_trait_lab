# Local Trait Lab

Android-first Flutter research prototype for comparing on-device emotion analysis backends with:

- single-image inference
- standardized seven-label emotion output
- benchmark execution over labeled datasets
- mock-first Gemma and EmotiEff integration seams

## Notes

- This project was created manually because Flutter tooling is not installed in the current environment.
- If you want full Android platform folders, run `flutter create --platforms=android .` inside this directory on a machine with Flutter installed, then keep the existing `lib/`, `test/`, and `pubspec.yaml`.
- The current implementation is mock-first and contains explicit TODO markers for real Gemma and EmotiEff runtime integration.

## Dataset format

```text
dataset/
  images/
  labels.csv
```

`labels.csv`:

```csv
file,label
images/img001.jpg,happy
images/img002.jpg,neutral
```
