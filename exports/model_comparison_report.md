# Local Trait Lab Benchmark Report

Generated: 2026-09-11T19:28:35+02:00

Benchmark runs: 4

## Model Comparison

| Rank | Model | Family | Dataset | Accuracy | Macro-F1 | Avg latency | Median latency | Evaluated | Failed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | enet_b2_7 | emotieff | affectnet7_25.zip | 0.686 | 0.685 | 1219.2 ms | 590.0 ms | 175 | 0 |
| 2 | resemotenet_kaggle_224 | emotieff | affectnet7_25.zip | 0.646 | 0.644 | 1338.7 ms | 713.0 ms | 175 | 0 |
| 3 | resemotenet_bs32 | emotieff | affectnet7_25.zip | 0.474 | 0.474 | 1182.3 ms | 534.0 ms | 175 | 0 |
| 4 | gemma_e2b | gemma | affectnet7_25.zip | 0.429 | 0.352 | 6931.1 ms | 6422.0 ms | 175 | 0 |

## Per-Class F1

| Model | angry | disgust | fear | happy | neutral | sad | surprise |
| --- | --- | --- | --- | --- | --- | --- | --- |
| enet_b2_7 | 0.607 | 0.667 | 0.759 | 0.826 | 0.558 | 0.766 | 0.615 |
| resemotenet_kaggle_224 | 0.619 | 0.711 | 0.512 | 0.821 | 0.575 | 0.667 | 0.600 |
| resemotenet_bs32 | 0.410 | 0.432 | 0.609 | 0.564 | 0.318 | 0.463 | 0.520 |
| gemma_e2b | 0.531 | 0.074 | 0.000 | 0.750 | 0.453 | 0.207 | 0.448 |

## Quick Read

- enet_b2_7: best classes: happy (0.826), sad (0.766); weakest classes: neutral (0.558), angry (0.607).
- resemotenet_kaggle_224: best classes: happy (0.821), disgust (0.711); weakest classes: fear (0.512), neutral (0.575).
- resemotenet_bs32: best classes: fear (0.609), happy (0.564); weakest classes: neutral (0.318), angry (0.410).
- gemma_e2b: best classes: happy (0.750), angry (0.531); weakest classes: fear (0.000), disgust (0.074).

## Notes

- Accuracy and macro-F1 are read from the app-exported benchmark summaries.
- Latency values were measured on the Android device during app-side inference.
- This report does not rerun inference; it only summarizes exported results.
