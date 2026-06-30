#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import torch
import onnx
from ResEmoteNetKaggle import ResEmoteNet


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument('checkpoint', type=Path)
    parser.add_argument('--output', type=Path, default=Path('ResEmoteNet/onnx/ResEmoteNetKaggle_224x224.onnx'))
    parser.add_argument('--input-size', type=int, default=224)
    parser.add_argument('--opset', type=int, default=18)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    model = ResEmoteNet(num_classes=7)
    state = torch.load(args.checkpoint, map_location='cpu')
    model.load_state_dict(state, strict=True)
    model.eval()

    dummy = torch.randn(1, 3, args.input_size, args.input_size, dtype=torch.float32)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        dummy,
        args.output.as_posix(),
        export_params=True,
        opset_version=args.opset,
        do_constant_folding=True,
        input_names=['input'],
        output_names=['logits'],
        dynamic_axes={'input': {0: 'batch'}, 'logits': {0: 'batch'}},
        external_data=False,
    )
    exported = onnx.load(args.output.as_posix())
    onnx.checker.check_model(exported)
    print(f'Exported {args.output} ({args.output.stat().st_size} bytes)')


if __name__ == '__main__':
    main()
