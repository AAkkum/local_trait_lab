#!/usr/bin/env python3
"""Export ResEmoteNet PyTorch checkpoints to ONNX.

The BS32/BS64/BS128 suffix describes the training batch size of the checkpoint.
It does not force the inference batch size. This exporter uses a dynamic batch
axis so the same ONNX model can run one image at a time in the Flutter app.
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "checkpoint",
        nargs="*",
        type=Path,
        help="One or more .pth checkpoints. Defaults to all ResEmoteNet*.pth files in this folder.",
    )
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--input-size", type=int, default=64, help="Square input size. Use the size used during training/preprocessing.")
    parser.add_argument("--opset", type=int, default=18)
    parser.add_argument("--no-dynamic-batch", action="store_true")
    parser.add_argument("--verify", action="store_true", help="Run onnx.checker after export. Requires the onnx package.")
    return parser.parse_args()


def load_model_class(script_path: Path) -> type:
    spec = importlib.util.spec_from_file_location("resemotenet_arch", script_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load architecture file: {script_path}")
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
        raise TypeError(
            "Checkpoint is not a state_dict-like object. "
            "If this is a full pickled model, export must be adapted to that exact object."
        )

    normalized: dict[str, Any] = {}
    for key, value in checkpoint.items():
        cleaned = key
        for prefix in ("module.", "model.", "net."):
            if cleaned.startswith(prefix):
                cleaned = cleaned[len(prefix) :]
        normalized[cleaned] = value
    return normalized


def export_checkpoint(checkpoint_path: Path, output_dir: Path, input_size: int, opset: int, dynamic_batch: bool, verify: bool) -> Path:
    import torch

    architecture_path = checkpoint_path.parent / "ResEmoteNet.py"
    ModelClass = load_model_class(architecture_path)

    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    state_dict = normalize_state_dict(checkpoint)

    model = ModelClass()
    missing, unexpected = model.load_state_dict(state_dict, strict=False)
    if missing or unexpected:
        print(f"Warning for {checkpoint_path.name}:")
        if missing:
            print(f"  missing keys: {missing[:10]}{' ...' if len(missing) > 10 else ''}")
        if unexpected:
            print(f"  unexpected keys: {unexpected[:10]}{' ...' if len(unexpected) > 10 else ''}")

    model.eval()
    dummy = torch.randn(1, 3, input_size, input_size, dtype=torch.float32)

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{checkpoint_path.stem}_{input_size}x{input_size}.onnx"

    dynamic_axes = None
    if dynamic_batch:
        dynamic_axes = {"input": {0: "batch"}, "logits": {0: "batch"}}

    torch.onnx.export(
        model,
        dummy,
        output_path.as_posix(),
        export_params=True,
        opset_version=opset,
        do_constant_folding=True,
        input_names=["input"],
        output_names=["logits"],
        dynamic_axes=dynamic_axes,
        external_data=False,
    )

    if verify:
        import onnx

        onnx_model = onnx.load(output_path.as_posix())
        onnx.checker.check_model(onnx_model)

    print(f"Exported {output_path}")
    return output_path


def main() -> None:
    args = parse_args()
    base_dir = Path(__file__).resolve().parent
    checkpoints = args.checkpoint or sorted(base_dir.glob("ResEmoteNet*.pth"))
    if not checkpoints:
        raise SystemExit("No checkpoints found.")

    output_dir = args.output_dir or (base_dir / "onnx")
    for checkpoint in checkpoints:
        export_checkpoint(
            checkpoint.resolve(),
            output_dir.resolve(),
            args.input_size,
            args.opset,
            dynamic_batch=not args.no_dynamic_batch,
            verify=args.verify,
        )


if __name__ == "__main__":
    main()
