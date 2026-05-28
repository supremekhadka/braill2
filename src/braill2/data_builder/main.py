from __future__ import annotations

import argparse
import os
import shutil
import sys

from .sources import angelina, dsbi, synthetic
from .splitter import (
    split_dataset,
    DEFAULT_TRAIN_RATIO,
    DEFAULT_VAL_RATIO,
    DEFAULT_TEST_RATIO,
    DEFAULT_SEED,
)
from .cropper import crop_dataset

IGNORE_DIRS: frozenset[str] = frozenset({
    ".gitignore",
    "pics",
    "src",
    "README.md",
    "train.txt",
    "val.txt",
    "test.txt",
    "figures",
})

DATASET_NAME_TO_ADAPTER = {
    "AngelinaDataset-master": "angelina",
    "DSBI-master": "dsbi",
}


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Build, split, and (optionally) crop the Braille dataset."
    )

    p.add_argument(
        "--raw-path",
        default="data/raw",
        help="Directory containing raw dataset archives (default: data/raw).",
    )

    p.add_argument(
        "--unified-path",
        default="data/unified",
        help="Output root for the unified dataset (default: data/unified).",
    )

    p.add_argument(
        "--split-path",
        default="data/split",
        help="Output root for the split dataset (default: data/split).",
    )

    p.add_argument(
        "--output-path",
        default="data/cropped",
        help="Final output root for cropped dataset (default: data/cropped).",
    )

    p.add_argument(
        "--angelina-prefix",
        default="ANG",
        help="Filename prefix for Angelina samples (default: ANG).",
    )

    p.add_argument(
        "--dsbi-prefix",
        default="DSBI",
        help="Filename prefix for DSBI samples (default: DSBI).",
    )

    p.add_argument(
        "--synthetic-prefix",
        default="SYN",
        help="Filename prefix for synthetic samples (default: SYN).",
    )

    p.add_argument(
        "--num-synthetic",
        type=int,
        default=0,
        help="Number of synthetic samples to generate (default: 0 = disabled).",
    )

    p.add_argument(
        "--train-ratio",
        type=float,
        default=DEFAULT_TRAIN_RATIO,
    )

    p.add_argument(
        "--val-ratio",
        type=float,
        default=DEFAULT_VAL_RATIO,
    )

    p.add_argument(
        "--test-ratio",
        type=float,
        default=DEFAULT_TEST_RATIO,
    )

    p.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help="Random seed for reproducibility (default: 42).",
    )

    p.add_argument(
        "--no-crop",
        action="store_true",
        help="Skip the cropping stage and use split output as final dataset.",
    )

    p.add_argument(
        "--crop-size",
        type=int,
        default=640,
        help="Crop side length in pixels.",
    )

    p.add_argument(
        "--crop-overlap",
        type=float,
        default=0.1,
        help="Overlap between adjacent crops as fraction of crop-size.",
    )

    p.add_argument(
        "--min-annotation-overlap",
        type=float,
        default=0.8,
        help="Min fraction of a box inside a crop to include it.",
    )

    p.add_argument(
        "--no-stratify",
        action="store_true",
        help="Disable stratified splitting (treat all sources as one pool).",
    )

    return p


def _run_sources(args: argparse.Namespace) -> None:
    """Convert all raw datasets into one unified flat dataset."""

    if not os.path.isdir(args.raw_path):
        print(f"[main] ERROR: raw path {args.raw_path!r} does not exist.", file=sys.stderr)
        sys.exit(1)

    print("\nBuilding unified dataset")

    for item in sorted(os.listdir(args.raw_path)):
        if item in IGNORE_DIRS:
            continue

        raw_dir = os.path.join(args.raw_path, item)

        if not os.path.isdir(raw_dir):
            continue

        adapter_name = DATASET_NAME_TO_ADAPTER.get(item)

        if adapter_name == "angelina":
            angelina.build(
                raw_dataset_path=raw_dir,
                output_root=args.unified_path,
                prefix=args.angelina_prefix,
                ignore_dirs=IGNORE_DIRS,
            )

        elif adapter_name == "dsbi":
            dsbi.build(
                raw_dataset_path=raw_dir,
                output_root=args.unified_path,
                prefix=args.dsbi_prefix,
                ignore_dirs=IGNORE_DIRS,
            )

        else:
            print(f"[main] Skipping unknown dataset: {item!r}")

    if args.num_synthetic > 0:
        _run_synthetic(args)

def _run_synthetic(args: argparse.Namespace) -> None:
    synthetic.build(
        output_root=args.unified_path,
        num_samples=args.num_synthetic,
        prefix=args.synthetic_prefix,
    )

def _run_split(args: argparse.Namespace) -> None:
    source_prefixes = {
        args.angelina_prefix: "angelina",
        args.dsbi_prefix: "dsbi",
        args.synthetic_prefix: "synthetic",
    }

    if not os.path.isdir(args.unified_path):
        print("[main] Skipping split: unified dataset directory not found.")
        return

    print("\nSplitting dataset")

    if os.path.isdir(args.split_path):
        shutil.rmtree(args.split_path)

    shutil.copytree(args.unified_path, args.split_path)

    split_dataset(
        dataset_dir=args.split_path,
        source_prefixes=source_prefixes,
        train_ratio=args.train_ratio,
        val_ratio=args.val_ratio,
        test_ratio=args.test_ratio,
        seed=args.seed,
        copy=False,
        stratify=not args.no_stratify,
    )


def _run_crop(args: argparse.Namespace) -> None:
    if not os.path.isdir(args.split_path):
        print("[main] Skipping crop: split dataset directory not found.")
        return

    print("\nCropping dataset")

    crop_dataset(
        dataset_dir=args.split_path,
        output_dir=args.output_path,
        crop_size=args.crop_size,
        overlap_ratio=args.crop_overlap,
        min_annotation_overlap=args.min_annotation_overlap,
    )


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    print("\n[Stage 1] Running source adapters")
    _run_sources(args)

    print("\n[Stage 2] Splitting dataset")
    _run_split(args)

    if args.no_crop:
        print("\n[Stage 3] Cropping skipped (--no-crop).")
        final_path = args.split_path
    else:
        print("\n[Stage 3] Cropping …")
        _run_crop(args)
        final_path = args.output_path

    print(f"  Pipeline complete. Final dataset in {final_path}")

if __name__ == "__main__":
    main()