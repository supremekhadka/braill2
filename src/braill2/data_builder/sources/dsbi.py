from __future__ import annotations

import os
import shutil
from pathlib import Path

from PIL import Image

from ..formats.models import BBox, Sample
from ..formats.yolo_io import write_label_file


_RECTO_SUFFIX = "recto"
_GRID_W_PAD = 0.80   # add 80 % of grid cell width
_GRID_H_PAD = 0.50   # add 50 % of grid cell height


def _parse_dsbi_boxes(label_path: str, img_w: int, img_h: int) -> list[BBox]:
    with open(label_path, "r") as fh:
        lines = fh.readlines()

    if len(lines) <= 3:
        return []

    v_lines = [int(x) for x in lines[1].strip().split()]
    h_lines = [int(x) for x in lines[2].strip().split()]

    boxes: list[BBox] = []

    for raw in lines[3:]:
        parts = raw.strip().split()
        if len(parts) < 8:
            continue

        row, col = int(parts[0]), int(parts[1])

        try:
            x1 = v_lines[2 * (col - 1)]
            x2 = v_lines[2 * (col - 1) + 1]
            y1 = h_lines[3 * (row - 1)]
            y2 = h_lines[3 * (row - 1) + 2]
        except IndexError:
            continue

        # Decode dot pattern (reversed binary)
        dots = "".join(parts[2:][::-1])
        cell_value = int(dots, 2)

        if cell_value == 0:
            continue  # empty cell → skip

        class_id = cell_value - 1

        w = float(x2 - x1)
        h = float(y2 - y1)
        cx_abs = float(x1) + w / 2
        cy_abs = float(y1) + h / 2

        # Expand bounding box by padding factors
        w_padded = w * (1 + _GRID_W_PAD)
        h_padded = h * (1 + _GRID_H_PAD)

        box = BBox(
            class_id=class_id,
            cx=cx_abs / img_w,
            cy=cy_abs / img_h,
            w=w_padded / img_w,
            h=h_padded / img_h,
        )
        if box.is_valid():
            boxes.append(box)

    return boxes


def build(
    raw_dataset_path: str,
    output_root: str,
    prefix: str = "DSBI",
    ignore_dirs: frozenset[str] | set[str] = frozenset()
) -> list[Sample]:
    images_out = os.path.join(output_root, "images")
    labels_out = os.path.join(output_root, "labels")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    samples: list[Sample] = []

    # DSBI tree depth: <dataset_root>/<group>/<book>/<file>
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

            # Index recto images and their matching annotation .txt files
            recto_images: dict[str, str] = {}   
            recto_labels: dict[str, str] = {}

            for fname in sorted(os.listdir(l2_path)):
                fpath = os.path.join(l2_path, fname)
                ext = Path(fname).suffix.lower()
                stem = Path(fname).stem

                # Only process recto pages
                try:
                    page_side = stem.rsplit("+", 1)[1]
                except IndexError:
                    continue
                if page_side != _RECTO_SUFFIX:
                    continue

                if ext == ".jpg":
                    recto_images[stem] = fpath
                elif ext == ".txt":
                    recto_labels[stem] = fpath

            # Convert matched pairs
            for stem, img_path in recto_images.items():
                ann_path = recto_labels.get(stem)
                if ann_path is None:
                    continue

                # Load image dimensions for normalisation
                with Image.open(img_path) as img:
                    img_w, img_h = img.size

                out_name = f"{prefix}_{Path(img_path).name}"
                dst_img = os.path.join(images_out, out_name)
                dst_lbl = os.path.join(labels_out, f"{prefix}_{stem}.txt")

                shutil.copy2(img_path, dst_img)

                boxes = _parse_dsbi_boxes(ann_path, img_w, img_h)
                write_label_file(boxes, dst_lbl)

                samples.append(
                    Sample(
                        image_path=dst_img,
                        label_path=dst_lbl,
                        source="dsbi",
                        annotations=boxes
                    )
                )

    print(f"[dsbi] Converted {len(samples)} samples: {output_root}")
    return samples