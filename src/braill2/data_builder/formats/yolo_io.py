from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

from .models import BBox, Sample

def read_label_file(label_path: str) -> list[BBox]:
    """Parse a YOLO .txt label file and return a list of BBox objects."""
    if not os.path.exists(label_path):
        return []

    boxes: list[BBox] = []
    with open(label_path, "r") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 5:
                continue
            try:
                class_id = int(parts[0])
                cx, cy, w, h = map(float, parts[1:])
                box = BBox(class_id=class_id, cx=cx, cy=cy, w=w, h=h)
                if box.is_valid():
                    boxes.append(box)
            except ValueError:
                continue

    return boxes


def read_sample(
    image_path: str,
    label_path: str,
    source: str
) -> Sample:
    """Build a Sample by reading the label file that accompanies an image."""
    annotations = read_label_file(label_path)
    return Sample(
        image_path=image_path,
        label_path=label_path,
        source=source,
        annotations=annotations,
    )


def write_label_file(boxes: Iterable[BBox], label_path: str) -> None:
    """Serialise a sequence of BBox objects to a YOLO .txt label file."""
    Path(label_path).parent.mkdir(parents=True, exist_ok=True)
    with open(label_path, "w") as fh:
        for box in boxes:
            fh.write(
                f"{box.class_id} "
                f"{box.cx:.6f} "
                f"{box.cy:.6f} "
                f"{box.w:.6f} "
                f"{box.h:.6f}\n"
            )


def write_sample(sample: Sample, images_root: str, labels_root: str) -> tuple[str, str]:
    img_name = Path(sample.image_path).name
    stem = Path(img_name).stem

    dst_label = os.path.join(labels_root, f"{stem}.txt")
    dst_image = os.path.join(images_root, img_name)

    write_label_file(sample.annotations, dst_label)
    return dst_image, dst_label


def iter_image_label_pairs(
    images_dir: str,
    labels_dir: str,
    image_extensions: tuple[str, ...] = (".jpg", ".jpeg", ".png"),
) -> Iterable[tuple[str, str]]:
    for fname in sorted(os.listdir(images_dir)):
        if not any(fname.lower().endswith(ext) for ext in image_extensions):
            continue
        stem = Path(fname).stem
        label_path = os.path.join(labels_dir, f"{stem}.txt")
        if os.path.exists(label_path):
            yield os.path.join(images_dir, fname), label_path


def validate_dataset_dir(images_dir: str, labels_dir: str) -> bool:
    images = {Path(f).stem for f in os.listdir(images_dir) if not os.path.isdir(os.path.join(images_dir, f))}
    labels = {Path(f).stem for f in os.listdir(labels_dir) if not os.path.isdir(os.path.join(labels_dir, f))}

    missing_labels = images - labels
    missing_images = labels - images

    ok = True
    if missing_labels:
        print(f"[validate] Images without labels ({len(missing_labels)}): {sorted(missing_labels)[:10]} ...")
        ok = False
    if missing_images:
        print(f"[validate] Labels without images ({len(missing_images)}): {sorted(missing_images)[:10]} ...")
        ok = False

    return ok