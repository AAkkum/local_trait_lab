#!/usr/bin/env python3
"""Summarize Local Trait Lab benchmark exports.

The Android app exports one JSON summary per benchmark run. This script scans
those summaries and writes a compact model-comparison report that can be used
for thesis notes, supervisor updates, or repository documentation.
"""
from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

EMOTION_LABELS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]


@dataclass(frozen=True)
class ClassMetrics:
    precision: float
    recall: float
    f1: float


@dataclass(frozen=True)
class BenchmarkRun:
    source_file: Path
    dataset: str
    model_id: str
    display_name: str
    family: str
    accuracy: float
    macro_f1: float
    average_latency_ms: float
    median_latency_ms: float
    evaluated_examples: int
    failed_examples: int
    per_class: dict[str, ClassMetrics]

    @property
    def effective_name(self) -> str:
        return self.display_name or self.model_id or self.source_file.parent.name


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "inputs",
        nargs="*",
        type=Path,
        default=[Path("exports")],
        help="Benchmark summary JSON files or folders to scan recursively.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("exports/model_comparison_report.md"),
        help="Markdown report path.",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=Path("exports/model_comparison_report.csv"),
        help="CSV comparison table path.",
    )
    return parser.parse_args()


def find_summary_files(inputs: Iterable[Path]) -> list[Path]:
    files: list[Path] = []
    for item in inputs:
        if item.is_file() and item.suffix.lower() == ".json":
            files.append(item)
        elif item.is_dir():
            files.extend(item.rglob("*_summary.json"))
    return sorted(set(files))


def as_float(value: Any, default: float = 0.0) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    return default


def as_int(value: Any, default: int = 0) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    return default


def parse_run(path: Path) -> BenchmarkRun:
    data = json.loads(path.read_text(encoding="utf-8"))
    dataset = data.get("dataset", {}) if isinstance(data.get("dataset"), dict) else {}
    model = data.get("model", {}) if isinstance(data.get("model"), dict) else {}
    metrics = data.get("metrics", {}) if isinstance(data.get("metrics"), dict) else {}
    per_class_data = metrics.get("per_class", {}) if isinstance(metrics.get("per_class"), dict) else {}

    per_class: dict[str, ClassMetrics] = {}
    for label in EMOTION_LABELS:
        raw = per_class_data.get(label, {})
        raw = raw if isinstance(raw, dict) else {}
        per_class[label] = ClassMetrics(
            precision=as_float(raw.get("precision")),
            recall=as_float(raw.get("recall")),
            f1=as_float(raw.get("f1")),
        )

    return BenchmarkRun(
        source_file=path,
        dataset=str(dataset.get("name", "unknown")),
        model_id=str(model.get("model_id", path.parent.name)),
        display_name=str(model.get("display_name", model.get("model_id", path.parent.name))),
        family=str(model.get("family", "unknown")),
        accuracy=as_float(metrics.get("accuracy")),
        macro_f1=as_float(metrics.get("macro_f1")),
        average_latency_ms=as_float(metrics.get("average_latency_ms")),
        median_latency_ms=as_float(metrics.get("median_latency_ms")),
        evaluated_examples=as_int(metrics.get("evaluated_examples")),
        failed_examples=as_int(metrics.get("failed_examples")),
        per_class=per_class,
    )


def fmt(value: float, digits: int = 3) -> str:
    return f"{value:.{digits}f}"


def worst_classes(run: BenchmarkRun, limit: int = 2) -> str:
    ordered = sorted(run.per_class.items(), key=lambda item: item[1].f1)
    return ", ".join(f"{label} ({fmt(score.f1)})" for label, score in ordered[:limit])


def best_classes(run: BenchmarkRun, limit: int = 2) -> str:
    ordered = sorted(run.per_class.items(), key=lambda item: item[1].f1, reverse=True)
    return ", ".join(f"{label} ({fmt(score.f1)})" for label, score in ordered[:limit])


def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    header = "| " + " | ".join(headers) + " |"
    separator = "| " + " | ".join("---" for _ in headers) + " |"
    body = ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join([header, separator, *body])


def build_markdown(runs: list[BenchmarkRun]) -> str:
    now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    ranked = sorted(runs, key=lambda run: (run.accuracy, run.macro_f1), reverse=True)

    lines: list[str] = [
        "# Local Trait Lab Benchmark Report",
        "",
        f"Generated: {now}",
        "",
        f"Benchmark runs: {len(runs)}",
        "",
    ]

    if not runs:
        lines.append("No benchmark summaries were found.")
        return "\n".join(lines) + "\n"

    lines.extend([
        "## Model Comparison",
        "",
        markdown_table(
            [
                "Rank",
                "Model",
                "Family",
                "Dataset",
                "Accuracy",
                "Macro-F1",
                "Avg latency",
                "Median latency",
                "Evaluated",
                "Failed",
            ],
            [
                [
                    str(index),
                    run.effective_name,
                    run.family,
                    run.dataset,
                    fmt(run.accuracy),
                    fmt(run.macro_f1),
                    f"{fmt(run.average_latency_ms, 1)} ms",
                    f"{fmt(run.median_latency_ms, 1)} ms",
                    str(run.evaluated_examples),
                    str(run.failed_examples),
                ]
                for index, run in enumerate(ranked, start=1)
            ],
        ),
        "",
        "## Per-Class F1",
        "",
        markdown_table(
            ["Model", *EMOTION_LABELS],
            [
                [run.effective_name, *[fmt(run.per_class[label].f1) for label in EMOTION_LABELS]]
                for run in ranked
            ],
        ),
        "",
        "## Quick Read",
        "",
    ])

    for run in ranked:
        lines.append(
            f"- {run.effective_name}: best classes: {best_classes(run)}; weakest classes: {worst_classes(run)}."
        )
    lines.append("")

    failed = [run for run in ranked if run.failed_examples > 0]
    if failed:
        lines.extend(["## Runs With Failed Examples", ""])
        for run in failed:
            lines.append(f"- {run.effective_name}: {run.failed_examples} failed examples.")
        lines.append("")

    lines.extend([
        "## Notes",
        "",
        "- Accuracy and macro-F1 are read from the app-exported benchmark summaries.",
        "- Latency values were measured on the Android device during app-side inference.",
        "- This report does not rerun inference; it only summarizes exported results.",
        "",
    ])
    return "\n".join(lines)


def write_csv(path: Path, runs: list[BenchmarkRun]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow([
            "model",
            "model_id",
            "family",
            "dataset",
            "accuracy",
            "macro_f1",
            "average_latency_ms",
            "median_latency_ms",
            "evaluated_examples",
            "failed_examples",
            *[f"f1_{label}" for label in EMOTION_LABELS],
        ])
        for run in sorted(runs, key=lambda item: (item.accuracy, item.macro_f1), reverse=True):
            writer.writerow([
                run.effective_name,
                run.model_id,
                run.family,
                run.dataset,
                fmt(run.accuracy, 6),
                fmt(run.macro_f1, 6),
                fmt(run.average_latency_ms, 3),
                fmt(run.median_latency_ms, 3),
                run.evaluated_examples,
                run.failed_examples,
                *[fmt(run.per_class[label].f1, 6) for label in EMOTION_LABELS],
            ])


def main() -> None:
    args = parse_args()
    summary_files = find_summary_files(args.inputs)
    runs = [parse_run(path) for path in summary_files]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(build_markdown(runs), encoding="utf-8")
    write_csv(args.csv, runs)

    print(f"Read {len(runs)} benchmark run(s).")
    print(f"Markdown report: {args.output}")
    print(f"CSV table: {args.csv}")


if __name__ == "__main__":
    main()
