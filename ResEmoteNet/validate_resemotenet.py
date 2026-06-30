#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import importlib.util
from pathlib import Path
from typing import Any

from PIL import Image
import torch

PAPER_LABELS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
REPO_LABELS = ["happy", "surprise", "sad", "angry", "disgust", "fear", "neutral"]

PREPROCESSORS = {
    "half": ([0.5, 0.5, 0.5], [0.5, 0.5, 0.5]),
    "imagenet": ([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    "none": ([0.0, 0.0, 0.0], [1.0, 1.0, 1.0]),
}


def load_model_class(script_path: Path) -> type:
    spec = importlib.util.spec_from_file_location("resemotenet_arch", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.ResEmoteNet


def normalize_state_dict(checkpoint: Any) -> dict[str, Any]:
    if isinstance(checkpoint, dict):
        for key in ("state_dict", "model_state_dict", "model", "net"):
            value = checkpoint.get(key)
            if isinstance(value, dict):
                checkpoint = value
                break
    if not isinstance(checkpoint, dict):
        raise TypeError("checkpoint is not a state_dict")
    out = {}
    for key, value in checkpoint.items():
        cleaned = key
        for prefix in ("module.", "model.", "net."):
            if cleaned.startswith(prefix):
                cleaned = cleaned[len(prefix):]
        out[cleaned] = value
    return out


def load_model(checkpoint_path: Path):
    Model = load_model_class(checkpoint_path.parent / "ResEmoteNet.py")
    model = Model()
    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    missing, unexpected = model.load_state_dict(normalize_state_dict(checkpoint), strict=False)
    if missing or unexpected:
        print(f"warning {checkpoint_path.name}: missing={len(missing)} unexpected={len(unexpected)}")
        if missing:
            print("  missing sample", missing[:5])
        if unexpected:
            print("  unexpected sample", unexpected[:5])
    model.eval()
    return model


def image_to_tensor(path: Path, size: int, preprocessor: str) -> torch.Tensor:
    image = Image.open(path).convert("RGB").resize((size, size), Image.BILINEAR)
    data = torch.ByteTensor(torch.ByteStorage.from_buffer(image.tobytes())).float()
    data = data.view(size, size, 3).permute(2, 0, 1) / 255.0
    mean, std = PREPROCESSORS[preprocessor]
    for channel in range(3):
        data[channel] = (data[channel] - mean[channel]) / std[channel]
    return data.unsqueeze(0)


def load_rows(dataset: Path):
    rows = []
    with (dataset / "labels.csv").open(newline="") as handle:
        for row in csv.DictReader(handle):
            rows.append((dataset / row["file"], row["label"]))
    return rows


def evaluate(model, rows, size: int, preprocessor: str, labels: list[str]):
    correct = 0
    counts = {label: 0 for label in labels}
    predictions = {label: 0 for label in labels}
    with torch.no_grad():
        for path, truth in rows:
            logits = model(image_to_tensor(path, size, preprocessor))
            index = int(logits.argmax(dim=1).item())
            pred = labels[index]
            counts[truth] = counts.get(truth, 0) + 1
            predictions[pred] = predictions.get(pred, 0) + 1
            correct += int(pred == truth)
    return correct / len(rows), predictions


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=Path("tools/affectnet7_25"))
    parser.add_argument("checkpoint", nargs="*", type=Path)
    args = parser.parse_args()
    checkpoints = args.checkpoint or sorted(Path("ResEmoteNet").glob("ResEmoteNetBS*.pth"))
    rows = load_rows(args.dataset)
    print(f"dataset={args.dataset} examples={len(rows)}")
    for checkpoint in checkpoints:
        print(f"\ncheckpoint={checkpoint.name}")
        model = load_model(checkpoint)
        for size in (64, 100, 224):
            for prep in PREPROCESSORS:
                for label_name, labels in (("paper", PAPER_LABELS), ("repo", REPO_LABELS)):
                    acc, preds = evaluate(model, rows, size, prep, labels)
                    top = sorted(preds.items(), key=lambda item: item[1], reverse=True)[:3]
                    print(f"size={size:3d} prep={prep:8s} labels={label_name:5s} acc={acc:.4f} top={top}")

if __name__ == "__main__":
    main()
