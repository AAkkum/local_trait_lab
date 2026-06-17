#!/usr/bin/env python3
"""Create a Local Trait Lab benchmark ZIP from a 7-class emotion dataset.

Supported inputs:
1. FER2013 CSV with columns: emotion,pixels,Usage
2. Folder tree with class folders named angry/disgust/fear/happy/neutral/sad/surprise
   either directly below root or below train/test/valid/validation folders.

Output ZIP structure:
  labels.csv
  images/<label>_<index>.png
"""
from __future__ import annotations

import argparse
import csv
import random
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit("Pillow is required: python3 -m pip install pillow") from exc

STANDARD_LABELS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
FER2013_LABELS = {
    "0": "angry",
    "1": "disgust",
    "2": "fear",
    "3": "happy",
    "4": "sad",
    "5": "surprise",
    "6": "neutral",
}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
SPLIT_NAMES = {"train", "training", "test", "validation", "valid", "val"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="FER2013 CSV or extracted dataset folder")
    parser.add_argument("--output", type=Path, default=Path("emotion_benchmark_sample.zip"))
    parser.add_argument("--split", default="test", help="CSV Usage or folder split to prefer, e.g. test/train/validation/all")
    parser.add_argument("--per-class", type=int, default=5, help="Maximum examples per class")
    parser.add_argument("--seed", type=int, default=42)
    return parser.parse_args()


def examples_from_csv(csv_path: Path, split: str) -> dict[str, list[Image.Image]]:
    examples: dict[str, list[Image.Image]] = defaultdict(list)
    wanted_split = split.lower()
    with csv_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"emotion", "pixels"}
        if not required.issubset(reader.fieldnames or set()):
            raise SystemExit(f"CSV must contain columns {sorted(required)}. Found: {reader.fieldnames}")
        for row in reader:
            usage = (row.get("Usage") or row.get("usage") or "").lower()
            if wanted_split != "all" and usage and wanted_split not in usage:
                continue
            label = FER2013_LABELS.get(str(row["emotion"]).strip())
            if label is None:
                continue
            pixels = [int(value) for value in row["pixels"].split()]
            if len(pixels) != 48 * 48:
                continue
            image = Image.new("L", (48, 48))
            image.putdata(pixels)
            examples[label].append(image.convert("RGB"))
    return examples


def candidate_roots(root: Path, split: str) -> Iterable[Path]:
    if split.lower() == "all":
        yield root
        for child in root.iterdir() if root.exists() else []:
            if child.is_dir() and child.name.lower() in SPLIT_NAMES:
                yield child
        return
    preferred = root / split
    if preferred.exists():
        yield preferred
    for name in SPLIT_NAMES:
        child = root / name
        if child.exists() and split.lower() in name.lower():
            yield child
    yield root


def examples_from_folders(root: Path, split: str) -> dict[str, list[Path]]:
    examples: dict[str, list[Path]] = defaultdict(list)
    seen_roots: set[Path] = set()
    for base in candidate_roots(root, split):
        if base in seen_roots:
            continue
        seen_roots.add(base)
        for label in STANDARD_LABELS:
            label_dir = base / label
            if not label_dir.exists():
                continue
            for path in sorted(label_dir.rglob("*")):
                if path.suffix.lower() in IMAGE_EXTENSIONS:
                    examples[label].append(path)
    return examples


def write_zip_from_csv(examples: dict[str, list[Image.Image]], output: Path, per_class: int, seed: int) -> None:
    rng = random.Random(seed)
    rows: list[tuple[str, str]] = []
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for label in STANDARD_LABELS:
            selected = list(examples.get(label, []))
            rng.shuffle(selected)
            for index, image in enumerate(selected[:per_class], start=1):
                relative = f"images/{label}_{index:03d}.png"
                with archive.open(relative, "w") as file:
                    image.save(file, format="PNG")
                rows.append((relative, label))
        _write_labels(archive, rows)


def write_zip_from_folders(examples: dict[str, list[Path]], output: Path, per_class: int, seed: int) -> None:
    rng = random.Random(seed)
    rows: list[tuple[str, str]] = []
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for label in STANDARD_LABELS:
            selected = list(examples.get(label, []))
            rng.shuffle(selected)
            for index, path in enumerate(selected[:per_class], start=1):
                relative = f"images/{label}_{index:03d}{path.suffix.lower()}"
                archive.write(path, relative)
                rows.append((relative, label))
        _write_labels(archive, rows)


def _write_labels(archive: zipfile.ZipFile, rows: list[tuple[str, str]]) -> None:
    if not rows:
        raise SystemExit("No examples found. Check input path, split, and class folder names.")
    content = "file,label\n" + "".join(f"{path},{label}\n" for path, label in rows)
    archive.writestr("labels.csv", content)


def main() -> None:
    args = parse_args()
    if args.input.is_file() and args.input.suffix.lower() == ".csv":
        examples = examples_from_csv(args.input, args.split)
        write_zip_from_csv(examples, args.output, args.per_class, args.seed)
    elif args.input.is_dir():
        examples = examples_from_folders(args.input, args.split)
        write_zip_from_folders(examples, args.output, args.per_class, args.seed)
    else:
        raise SystemExit("Input must be a FER2013 CSV or an extracted dataset folder.")
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
