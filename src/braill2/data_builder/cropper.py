import os
from pathlib import Path
from typing import Iterator

import cv2

from .formats.models import BBox
from .formats.yolo_io import read_label_file, write_label_file


class BrailleCropper:
    def __init__(
        self,
        crop_size: int = 640,
        overlap_ratio: float = 0.1,
        min_annotation_overlap: float = 0.8,
    ) -> None:
        self.crop_size = crop_size
        self.overlap_ratio = overlap_ratio
        self.min_annotation_overlap = min_annotation_overlap

    def _crop_positions(
        self, img_h: int, img_w: int
    ) -> list[tuple[int, int, int, int]]:
        """Return (y1, y2, x1, x2) for every sliding-window position."""
        step = max(int(self.crop_size * (1 - self.overlap_ratio)), 1)

        def positions(total: int) -> list[int]:
            pts = list(range(0, total - self.crop_size + 1, step))
            if not pts:
                return [0]
            if pts[-1] + self.crop_size < total:
                pts.append(total - self.crop_size)
            return pts

        crops = []
        for y in positions(img_h):
            for x in positions(img_w):
                crops.append((
                    y,
                    min(y + self.crop_size, img_h),
                    x,
                    min(x + self.crop_size, img_w),
                ))
        return crops

    def _overlap_ratio(
        self,
        box: BBox,
        crop: tuple[int, int, int, int],
        img_w: int,
        img_h: int,
    ) -> float:
        y1, y2, x1, x2 = crop
        bx1, by1, bx2, by2 = box.to_corners_abs(img_w, img_h)

        inter_x1 = max(bx1, x1)
        inter_y1 = max(by1, y1)
        inter_x2 = min(bx2, x2)
        inter_y2 = min(by2, y2)

        if inter_x2 <= inter_x1 or inter_y2 <= inter_y1:
            return 0.0

        intersection = (inter_x2 - inter_x1) * (inter_y2 - inter_y1)
        box_area = (bx2 - bx1) * (by2 - by1)
        return 0.0 if box_area <= 0 else intersection / box_area

    def _clip_to_crop(
        self,
        box: BBox,
        crop: tuple[int, int, int, int],
        img_w: int,
        img_h: int,
    ) -> BBox | None:
        y1, y2, x1, x2 = crop
        crop_h = y2 - y1
        crop_w = x2 - x1

        if crop_h <= 0 or crop_w <= 0:
            return None

        bx1, by1, bx2, by2 = box.to_corners_abs(img_w, img_h)

        # Clip and shift to crop-local origin
        cx1 = max(bx1, x1) - x1
        cy1 = max(by1, y1) - y1
        cx2 = min(bx2, x2) - x1
        cy2 = min(by2, y2) - y1

        if cx2 <= cx1 or cy2 <= cy1:
            return None

        return BBox(
            class_id=box.class_id,
            cx=(cx1 + cx2) / 2 / crop_w,
            cy=(cy1 + cy2) / 2 / crop_h,
            w=(cx2 - cx1) / crop_w,
            h=(cy2 - cy1) / crop_h,
        )

    def crop_image(
        self,
        image_path: str,
        label_path: str,
        output_images_dir: str,
        output_labels_dir: str,
        prefix: str = "",
    ) -> int:
        img = cv2.imread(image_path)
        if img is None:
            raise FileNotFoundError(f"Cannot read image: {image_path!r}")

        img_h, img_w = img.shape[:2]

        boxes = read_label_file(label_path)
        crops = self._crop_positions(img_h, img_w)

        os.makedirs(output_images_dir, exist_ok=True)
        os.makedirs(output_labels_dir, exist_ok=True)

        base = (f"{prefix}." if prefix else "") + Path(image_path).stem

        for i, crop in enumerate(crops):
            y1, y2, x1, x2 = crop
            cropped_img = img[y1:y2, x1:x2]

            # Ensure output is exactly crop_size × crop_size
            if cropped_img.shape[:2] != (self.crop_size, self.crop_size):
                cropped_img = cv2.resize(
                    cropped_img, (self.crop_size, self.crop_size)
                )

            # Filter and re-normalise annotations
            adjusted: list[BBox] = []
            for box in boxes:
                if (
                    self._overlap_ratio(box, crop, img_w, img_h)
                    >= self.min_annotation_overlap
                ):
                    clipped = self._clip_to_crop(box, crop, img_w, img_h)
                    if clipped is not None:
                        adjusted.append(clipped)

            out_stem = f"{base}_{i:02d}"
            cv2.imwrite(
                os.path.join(output_images_dir, f"{out_stem}.jpg"), cropped_img
            )
            write_label_file(
                adjusted, os.path.join(output_labels_dir, f"{out_stem}.txt")
            )

        return len(crops)
    

def _iter_split_pairs(
    images_dir: str,
    labels_dir: str,
) -> Iterator[tuple[str, str, str]]:
    for split in ("train", "val", "test"):
        split_img_dir = os.path.join(images_dir, split)
        split_lbl_dir = os.path.join(labels_dir, split)
        if not os.path.isdir(split_img_dir):
            continue
        for fname in sorted(os.listdir(split_img_dir)):
            if not any(
                fname.lower().endswith(ext) for ext in (".jpg", ".jpeg", ".png")
            ):
                continue
            img_path = os.path.join(split_img_dir, fname)
            lbl_path = os.path.join(split_lbl_dir, Path(fname).stem + ".txt")
            if not os.path.exists(lbl_path):
                lbl_path = ""
            yield split, img_path, lbl_path


def crop_dataset(
    dataset_dir: str,
    output_dir: str,
    crop_size: int = 640,
    overlap_ratio: float = 0.1,
    min_annotation_overlap: float = 0.8,
    process_missing_annotations: bool = True,
) -> dict[str, int]:
    cropper = BrailleCropper(
        crop_size=crop_size,
        overlap_ratio=overlap_ratio,
        min_annotation_overlap=min_annotation_overlap,
    )

    images_dir = os.path.join(dataset_dir, "images")
    labels_dir = os.path.join(dataset_dir, "labels")

    totals: dict[str, int] = {"train": 0, "val": 0, "test": 0}
    skipped = 0

    for split, img_path, lbl_path in _iter_split_pairs(images_dir, labels_dir):
        if not lbl_path:
            if not process_missing_annotations:
                skipped += 1
                continue
            # Proceed with an empty label (cropper writes empty .txt files)
            lbl_path = ""

        out_img_dir = os.path.join(output_dir, "images", split)
        out_lbl_dir = os.path.join(output_dir, "labels", split)

        # Use two-character relative prefix derived from split name
        prefix = split[:2].upper()

        n = cropper.crop_image(
            image_path=img_path,
            label_path=lbl_path,
            output_images_dir=out_img_dir,
            output_labels_dir=out_lbl_dir,
            prefix=prefix,
        )
        totals[split] += n

    print("[cropper] Cropping complete:")
    for split_name, count in totals.items():
        print(f"  {split_name:5s}: {count} crops")
    if skipped:
        print(f"  skipped (missing labels): {skipped}")

    return totals