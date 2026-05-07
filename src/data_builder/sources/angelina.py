from __future__ import annotations

import os
import shutil
from pathlib import Path

from ..formats.models import BBox, Sample
from ..formats.yolo_io import write_label_file

_ANGELINA_EXTENSIONS = {".jpg", ".jpeg", ".png"}
_ANGELINA_LABEL_EXT = ".csv"


def _parse_csv(label_path: str) -> list[BBox]:
    boxes: list[BBox] = []
    with open(label_path, "r") as fh:
        for raw_line in fh:
            line = raw_line.strip()
            if not line:
                continue
            x1_s, y1_s, x2_s, y2_s, c_s = line.split(";")
            x1, y1, x2, y2 = float(x1_s), float(y1_s), float(x2_s), float(y2_s)
            class_id = int(c_s) - 1

            width = x2 - x1
            height = y2 - y1
            if width <= 0 or height <= 0:
                continue

            cx = x1 + width / 2
            cy = y1 + height / 2
            boxes.append(BBox(class_id=class_id, cx=cx, cy=cy, w=width, h=height))

    return boxes


def build(
    raw_dataset_path: str,
    output_root: str,
    prefix: str = "ANG",
    ignore_dirs: frozenset[str] | set[str] = frozenset()
) -> list[Sample]:
    images_out = os.path.join(output_root, "images")
    labels_out = os.path.join(output_root, "labels")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    samples: list[Sample] = []

    # Angelina tree depth: <dataset_root>/<split_group>/<book>/<file>
    for level1 in sorted(os.listdir(raw_dataset_path)):
        if level1 in ignore_dirs:
            continue
        l1_path = os.path.join(raw_dataset_path, level1)
        if not os.path.isdir(l1_path):
            continue

        for level2 in sorted(os.listdir(l1_path)):
            if level2 in ignore_dirs:
                continue
            l2_path = os.path.join(l1_path, level2)
            if not os.path.isdir(l2_path):
                continue

            images_in_dir: dict[str, str] = {}  
            csvs_in_dir: dict[str, str] = {}

            for fname in os.listdir(l2_path):
                if fname in ignore_dirs:
                    continue
                fpath = os.path.join(l2_path, fname)
                ext = Path(fname).suffix.lower()
                stem = Path(fname).stem
                if ext in _ANGELINA_EXTENSIONS:
                    images_in_dir[stem] = fpath
                elif ext == _ANGELINA_LABEL_EXT:
                    csvs_in_dir[stem] = fpath

            for stem, img_path in images_in_dir.items():
                csv_path = csvs_in_dir.get(stem)
                if csv_path is None:
                    continue  

                out_name = f"{prefix}_{Path(img_path).name}"
                dst_img = os.path.join(images_out, out_name)
                dst_lbl = os.path.join(labels_out, f"{prefix}_{stem}.txt")

                shutil.copy2(img_path, dst_img)

                boxes = _parse_csv(csv_path)
                write_label_file(boxes, dst_lbl)

                samples.append(
                    Sample(
                        image_path=dst_img,
                        label_path=dst_lbl,
                        source="angelina",
                        annotations=boxes,
                    )
                )

    print(f"[angelina] Converted {len(samples)} samples: {output_root}")
    return samples