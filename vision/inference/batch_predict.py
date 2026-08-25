"""
Run inference on every image in a folder and write one CSV per image.

Place this file at:  vision/inference/batch_predict.py
(next to pipeline.py, predict.py, schemas.py)

Run it as a module, same convention as predict.py:
    python -m vision.inference.batch_predict \
        --input-dir data/images \
        --output-dir data/output/csv

Why this guarantees every inference goes through SAHI:
    pipeline_batch() (in pipeline.py) is the single entry point used here.
    For every image it calls processing/sahi_inference.run_sliced_inference(),
    which wraps SAHI's get_sliced_prediction(). There is no code path in
    pipeline_batch that bypasses SAHI, so batching over a folder this way
    routes every image through the same sliced-inference logic used for
    single-image predict.py runs. The model + label map are also loaded
    only once and reused across the whole folder.
"""

import argparse
import csv
from pathlib import Path

from .pipeline import pipeline_batch

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}


def find_images(folder: Path) -> list[Path]:
    images = sorted(
        p for p in folder.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS
    )
    return images


def write_csv(path: Path, annotations: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = ["class_id", "x1", "y1", "x2", "y2"]
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in annotations:
            writer.writerow(row)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Run SAHI-backed inference on a folder of images, "
                     "writing one CSV of detections per image."
    )
    p.add_argument("--input-dir", type=str, required=True,
                    help="Folder containing images to run inference on.")
    p.add_argument("--output-dir", type=str, required=True,
                    help="Folder to write one CSV per image into (created if missing).")

    p.add_argument("--model", type=str,
                    default="weights/deployment/yolo26n/finetuned/best_finetuned_mAP_96_1.pt")
    p.add_argument("--label-map", type=str, default="configs/braille.yaml")

    p.add_argument("--slice-size", type=int, default=640)
    p.add_argument("--overlap", type=float, default=0.1)
    p.add_argument("--confidence", type=float, default=0.4)
    p.add_argument("--nms-iou", type=float, default=0.1)
    p.add_argument("--device", type=str, default="cuda")

    return p


def main() -> None:
    args = build_parser().parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not input_dir.is_dir():
        raise SystemExit(f"Input dir not found: {input_dir}")

    image_paths = find_images(input_dir)
    if not image_paths:
        raise SystemExit(f"No images found in {input_dir}")

    cfg = {
        "model": args.model,
        "label_map": args.label_map,
        "slice_size": args.slice_size,
        "overlap": args.overlap,
        "confidence": args.confidence,
        "nms_iou": args.nms_iou,
    }

    print(f"Found {len(image_paths)} images. Loading model once and running "
          f"sliced (SAHI) inference on each...")

    results = pipeline_batch(
        [str(p) for p in image_paths],
        cfg,
        device=args.device,
    )

    for image_path, result in zip(image_paths, results):
        csv_path = output_dir / f"{image_path.stem}.csv"
        write_csv(csv_path, result["annotations"])

        final_count = (
            result["raw_detections"]
            - result["outliers_removed"]
            - result["nms_removed"]
        )
        print(
            f"{image_path.name}: raw={result['raw_detections']} "
            f"nms_removed={result['nms_removed']} "
            f"final={final_count} -> {csv_path}"
        )

    print(f"Done. Wrote {len(image_paths)} CSVs to {output_dir}")


if __name__ == "__main__":
    main()