#!/usr/bin/env python3
"""Create a Local Trait Lab benchmark folder from an AffectNet-style dataset.

Expected input layout:
  affectnet/
    anger/
    contempt/
    disgust/
    fear/
    happy/
    neutral/
    sad/
    surprise/

The output is a folder that the app can import directly:
  output/
    labels.csv
    images/<label>_<index>.<ext>

By default this creates an AffectNet-7 benchmark and excludes contempt.
The AffectNet folder name "anger" is mapped to the app label "angry".
"""
from __future__ import annotations

import argparse
import csv
import random
import shutil
from pathlib import Path

STANDARD_LABELS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
AFFECTNET_FOLDER_TO_LABEL = {
    "anger": "angry",
    "angry": "angry",
    "disgust": "disgust",
    "fear": "fear",
    "happy": "happy",
    "neutral": "neutral",
    "sad": "sad",
    "surprise": "surprise",
}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="AffectNet-style root folder with class subfolders")
    parser.add_argument("--output", type=Path, default=Path("affectnet7_benchmark"))
    parser.add_argument("--per-class", type=int, default=500, help="Number of images to sample per class")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Delete the output folder first if it already exists",
    )
    return parser.parse_args()


def collect_examples(root: Path) -> dict[str, list[Path]]:
    examples = {label: [] for label in STANDARD_LABELS}
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"Input folder does not exist: {root}")

    for folder_name, label in AFFECTNET_FOLDER_TO_LABEL.items():
        folder = root / folder_name
        if not folder.exists():
            continue
        for path in sorted(folder.rglob("*")):
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
                examples[label].append(path)

    missing = [label for label, paths in examples.items() if not paths]
    if missing:
        raise SystemExit(f"No images found for labels: {', '.join(missing)}")
    return examples


def prepare_output(output: Path, overwrite: bool) -> Path:
    if output.exists():
        if not overwrite:
            raise SystemExit(f"Output already exists: {output}. Use --overwrite to replace it.")
        shutil.rmtree(output)
    images_dir = output / "images"
    images_dir.mkdir(parents=True)
    return images_dir


def build_benchmark(root: Path, output: Path, per_class: int, seed: int, overwrite: bool) -> None:
    if per_class <= 0:
        raise SystemExit("--per-class must be greater than zero")

    examples = collect_examples(root)
    images_dir = prepare_output(output, overwrite)
    rng = random.Random(seed)
    rows: list[tuple[str, str]] = []

    for label in STANDARD_LABELS:
        candidates = list(examples[label])
        rng.shuffle(candidates)
        selected = candidates[:per_class]
        if len(selected) < per_class:
            print(f"Warning: requested {per_class} images for {label}, found {len(selected)}")

        for index, source in enumerate(selected, start=1):
            extension = source.suffix.lower()
            relative = Path("images") / f"{label}_{index:05d}{extension}"
            shutil.copy2(source, output / relative)
            rows.append((relative.as_posix(), label))

    labels_path = output / "labels.csv"
    with labels_path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["file", "label"])
        writer.writerows(rows)

    print(f"Wrote {len(rows)} examples to {output}")
    print(f"Labels: {labels_path}")


def main() -> None:
    args = parse_args()
    build_benchmark(args.input, args.output, args.per_class, args.seed, args.overwrite)


if __name__ == "__main__":
    main()
