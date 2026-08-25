from __future__ import annotations

import os
import random

import cv2
import numpy as np

from ..schemas import BBox, Sample
from ..file_utils import write_label_file
from .synthetic import BrailleGenerator          # <-- adjust to your actual module name
from .nepali_braille_map import text_to_words, SPACE


class NepaliBrailleGenerator(BrailleGenerator):
    """
    BrailleGenerator subclass that lays out real, meaningful Nepali text
    (converted to Braille cells via `nepali_braille_map.text_to_words`)
    instead of BrailleGenerator's uniformly-random `allowed_chars`
    sampling -- while reusing the exact same physical rendering pipeline
    (embossed bump shapes, wear/smear/tear degradation, lighting, paper
    texture, perspective warp) unchanged, so text pages are visually and
    statistically consistent with random-cell pages from the base class.

    Only the RECTO (front, annotated/labelled) side is driven by real
    text. The VERSO (back-side bleed-through) layer still uses random
    cells exactly as in the base class, since it represents unrelated
    content bleeding faintly through the paper, not a second copy of the
    same text.
    """

    def generate_text_page(
        self,
        text: str,
        margin_mm: float = 20.0,
        apply_skew: bool = True,
        verso_space_prob: float = 0.15,
    ) -> tuple[np.ndarray, list[str], str]:
        """
        Render as much of `text` as fits on one page, word-wrapped so
        that no word's cells are ever split across two pages.

        Returns (image, yolo_annotation_lines, leftover_text); the
        caller re-feeds `leftover_text` into the next page/call to
        paginate an arbitrarily long corpus (see `build_text_dataset`).
        """
        recto_h = np.zeros(self.img_size, dtype=np.float32)
        verso_h = np.zeros(self.img_size, dtype=np.float32)

        _bump_template = self.create_embossed_bump(self.dot_rad)
        bh, bw = _bump_template.shape
        offset = bh // 2

        verso_dot_scale = random.uniform(0.75, 0.9)
        _verso_bump_template = self.create_embossed_bump(self.dot_rad * verso_dot_scale)
        verso_bh, verso_bw = _verso_bump_template.shape
        verso_offset = verso_bh // 2

        margin = int(margin_mm * self.scale)
        cols = int((self.img_size[1] - 2 * margin) // self.px_cell_w)
        rows = int((self.img_size[0] - 2 * margin) // self.px_line_h)

        raw_bboxes: list[tuple[int, float, float, float, float]] = []

        recto_smear_p = random.uniform(0.1, 0.6)
        recto_worn_p = min(recto_smear_p + random.uniform(0.1, 0.4), 1.0)
        verso_torn_p = random.uniform(0.0, 0.15)
        verso_smear_p = min(verso_torn_p + random.uniform(0.1, 0.4), 1.0)
        verso_worn_p = min(verso_smear_p + random.uniform(0.1, 0.4), 1.0)

        # ---- word-wrap real text onto the (row, col) grid ---------------
        words = text.split()
        word_ids = text_to_words(text)

        placements: list[tuple[int, int, int]] = []   # (row, col, char_id)
        r, c = 0, 0
        used_words = 0
        for w_ids in word_ids:
            if not w_ids:
                used_words += 1
                continue
            wlen = len(w_ids)
            if wlen > cols:                     # pathologically long "word"
                w_ids = w_ids[:cols]
                wlen = len(w_ids)
            if c != 0 and c + wlen > cols:       # doesn't fit on this line
                r += 1
                c = 0
            if r >= rows:
                break
            for cid in w_ids:
                placements.append((r, c, cid))
                c += 1
            used_words += 1
            c += 1                               # one blank cell of spacing
            if c >= cols:
                r += 1
                c = 0
        leftover_text = " ".join(words[used_words:])

        # ---- stamp the real text onto the recto layer -------------------
        for (r, c, char_id) in placements:
            px = margin + c * self.px_cell_w
            py = margin + r * self.px_line_h
            bit_str = self.id_to_bits(char_id)

            x1 = px - self.dot_rad - self.bbox_pad
            y1 = py - self.dot_rad - self.bbox_pad
            x2 = px + self.px_h_dot + self.dot_rad + self.bbox_pad
            y2 = py + 2 * self.px_v_dot + self.dot_rad + self.bbox_pad
            raw_bboxes.append((char_id, x1, y1, x2, y2))

            top_ratio = (random.uniform(0.1, 0.45) if self.scale >= 10
                         else random.uniform(0.5, 0.7))
            bump = self.create_embossed_bump(
                self.dot_rad, top_ratio=top_ratio,
                falloff_power=random.uniform(0.6, 0.8),
            )
            cell_roll = random.random()
            if cell_roll < recto_smear_p:
                cell_bump = self.degrade_bump(bump, "smear")
            elif cell_roll < recto_worn_p:
                cell_bump = self.degrade_bump(bump, "worn")
            else:
                cell_bump = bump

            for i, bit in enumerate(bit_str):
                if bit != "1":
                    continue
                jx = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                jy = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                dx = (i // 3) * self.px_h_dot + jx
                dy = (i % 3) * self.px_v_dot + jy
                y_c, x_c = int(py + dy), int(px + dx)
                y1_b, y2_b = y_c - offset, y_c + offset + 1
                x1_b, x2_b = x_c - offset, x_c + offset + 1
                if (0 <= y1_b and y2_b < self.img_size[0]
                        and 0 <= x1_b and x2_b < self.img_size[1]):
                    recto_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                        recto_h[y1_b:y2_b, x1_b:x2_b], cell_bump
                    )

        # ---- verso: random bleed-through, identical to the base class ---
        for r in range(rows):
            for c in range(cols):
                if random.random() <= verso_space_prob:
                    continue
                px = margin + c * self.px_cell_w
                py = margin + r * self.px_line_h
                v_char_id = random.randint(0, 62)
                v_bit_str = self.id_to_bits(v_char_id)
                vx = px + self.px_h_dot / 2
                vy = py + self.px_v_dot / 2

                verso_top_ratio = (random.uniform(0.1, 0.45) if self.scale >= 10
                                    else random.uniform(0.5, 0.7))
                verso_bump = self.create_embossed_bump(
                    self.dot_rad * verso_dot_scale, top_ratio=verso_top_ratio,
                    falloff_power=random.uniform(0.6, 0.8),
                )
                verso_cell_roll = random.random()
                if verso_cell_roll < verso_torn_p:
                    verso_cell_bump = self.degrade_bump(verso_bump, "torn")
                elif verso_cell_roll < verso_smear_p:
                    verso_cell_bump = self.degrade_bump(verso_bump, "smear")
                elif verso_cell_roll < verso_worn_p:
                    verso_cell_bump = self.degrade_bump(verso_bump, "worn")
                else:
                    verso_cell_bump = verso_bump

                for i, bit in enumerate(v_bit_str):
                    if bit != "1":
                        continue
                    jx = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                    jy = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                    dx = (i // 3) * self.px_h_dot + jx
                    dy = (i % 3) * self.px_v_dot + jy
                    y_c, x_c = int(vy + dy), int(vx + dx)
                    y1_b, y2_b = y_c - verso_offset, y_c + verso_offset + 1
                    x1_b, x2_b = x_c - verso_offset, x_c + verso_offset + 1
                    if (0 <= y1_b and y2_b < self.img_size[0]
                            and 0 <= x1_b and x2_b < self.img_size[1]):
                        verso_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                            verso_h[y1_b:y2_b, x1_b:x2_b], verso_cell_bump
                        )

        # ---- from here on: identical post-processing to generate_page ---
        wear_map = self.generate_wear_map()
        wear_strength = 0.5
        recto_h *= (1.0 - wear_map * wear_strength)
        total_h = recto_h * 1.0 - verso_h * 0.8
        blur_px = 1
        total_h = cv2.GaussianBlur(total_h, (blur_px, blur_px), 0)

        light_azimuth = random.uniform(205, 335)
        light_elevation = random.uniform(0, 45)
        light_intensity = random.uniform(0.25, 0.55)

        shading = self.calculate_lighting(
            total_h, azimuth_deg=light_azimuth,
            elevation_deg=light_elevation, intensity=light_intensity,
        )

        shadow_dist = 0.9 * self.scale
        az_rad = np.radians(light_azimuth)
        dx_s = -np.cos(az_rad) * shadow_dist
        dy_s = -np.sin(az_rad) * shadow_dist
        M_shadow = np.float32([[1, 0, dx_s], [0, 1, dy_s]])
        recto_shadow = cv2.warpAffine(recto_h, M_shadow, (self.img_size[1], self.img_size[0]))

        blur_size = int(self.scale * 2.5)
        if blur_size % 2 == 0:
            blur_size += 1
        recto_shadow = cv2.GaussianBlur(recto_shadow, (blur_size, blur_size), 0)
        recto_shadow = np.clip(recto_shadow - recto_h, 0, 1)

        shadow_intensity = min(light_intensity * random.uniform(0.3, 0.6), 0.15)
        shading -= recto_shadow * shadow_intensity

        light_gradient = self.generate_light_gradient(light_azimuth, strength=random.uniform(0.15, 0.25))

        verso_darkness_factor = random.uniform(0.15, 0.35)
        final = self.generate_paper_texture() + shading + light_gradient - (verso_h * verso_darkness_factor)
        final = self.apply_vignette(final, strength=0.25)

        final_bgr = np.stack([final, final, final], axis=-1)
        final_bgr = self.apply_color_tint(final_bgr)

        M = None
        if apply_skew:
            final_bgr, M = self.apply_perspective_skew(final_bgr, max_skew_px=80, max_rot_deg=2.5)

        img_h, img_w = final_bgr.shape[:2]
        yolo_annotations: list[str] = []
        for char_id, x1, y1, x2, y2 in raw_bboxes:
            if M is not None:
                pts = np.float32([[x1, y1], [x2, y1], [x2, y2], [x1, y2]]).reshape(-1, 1, 2)
                warped_pts = cv2.perspectiveTransform(pts, M)
                x1 = float(warped_pts[:, 0, 0].min())
                y1 = float(warped_pts[:, 0, 1].min())
                x2 = float(warped_pts[:, 0, 0].max())
                y2 = float(warped_pts[:, 0, 1].max())

            x1, x2 = max(0.0, x1), min(float(img_w), x2)
            y1, y2 = max(0.0, y1), min(float(img_h), y2)
            w = x2 - x1
            h = y2 - y1
            if w <= 0 or h <= 0:
                continue
            xc = (x1 + w / 2) / img_w
            yc = (y1 + h / 2) / img_h
            yolo_annotations.append(f"{char_id} {xc:.6f} {yc:.6f} {w / img_w:.6f} {h / img_h:.6f}")

        final_uint8 = (np.clip(final_bgr, 0, 1) * 255).astype(np.uint8)
        if self.supersample > 1:
            final_uint8 = cv2.resize(
                final_uint8, (self.output_size[1], self.output_size[0]),
                interpolation=cv2.INTER_AREA,
            )

        return final_uint8, yolo_annotations, leftover_text


def _parse_yolo_strings(annotation_strings: list[str]) -> list[BBox]:
    boxes: list[BBox] = []
    for line in annotation_strings:
        parts = line.strip().split()
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


def load_corpus(text_source: str) -> str:
    """Accept either a path to a .txt file or a raw text blob directly."""
    if os.path.isfile(text_source):
        with open(text_source, encoding="utf-8") as f:
            return f.read()
    return text_source


def build_text_dataset(
    output_root: str,
    text_source: str,
    prefix: str = "NEP",
    generator: NepaliBrailleGenerator | None = None,
    seed: int | None = None,
    background_dir: str | None = None,
    max_pages: int | None = None,
    **generator_kwargs,
) -> list[Sample]:
    """
    Paginate `text_source` (a file path, or a raw string of Nepali text --
    ideally several sentences/paragraphs long) across as many synthetic
    pages as needed, rendering each with `NepaliBrailleGenerator` and
    writing images + YOLO label files exactly like the base module's
    `build()`, so the two dataset styles (random-cell and real-text) drop
    into the same downstream training pipeline.

    Set `max_pages` to cap output for a quick smoke test.
    """
    if generator is None:
        generator = NepaliBrailleGenerator(seed=seed, background_dir=background_dir, **generator_kwargs)

    images_out = os.path.join(output_root, "images")
    labels_out = os.path.join(output_root, "labels")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    remaining = load_corpus(text_source).replace("\n", " ")
    samples: list[Sample] = []
    page_idx = 0

    while remaining.strip():
        if max_pages is not None and page_idx >= max_pages:
            break

        img_bgr, annotation_strings, remaining = generator.generate_text_page(remaining)
        if not annotation_strings:
            # Nothing fit (e.g. a single word wider than the page) --
            # avoid an infinite loop on unusable input.
            break

        base_name = f"{prefix}_{page_idx:05d}"
        dst_img = os.path.join(images_out, f"{base_name}.jpg")
        dst_lbl = os.path.join(labels_out, f"{base_name}.txt")

        cv2.imwrite(dst_img, img_bgr)
        boxes = _parse_yolo_strings(annotation_strings)
        write_label_file(boxes, dst_lbl)

        samples.append(
            Sample(image_path=dst_img, label_path=dst_lbl, source="synthetic_text", annotations=boxes)
        )

        page_idx += 1
        if page_idx % 10 == 0:
            print(f"[nepali_text] {page_idx} pages generated, "
                  f"{len(remaining.split())} words remaining")

    print(f"[nepali_text] Done: {page_idx} pages written to {output_root}")
    return samples

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate a synthetic Nepali Braille dataset."
    )

    parser.add_argument(
        "output_root",
        type=str,
        help="Directory where images/ and labels/ will be created.",
    )

    parser.add_argument(
        "text_source",
        type=str,
        help="Path to a .txt file containing Nepali text, or raw Nepali text.",
    )

    parser.add_argument(
        "--prefix",
        type=str,
        default="NEP",
        help="Prefix for generated filenames.",
    )

    parser.add_argument(
        "--max_pages",
        type=int,
        default=None,
        help="Maximum number of pages to generate.",
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed for reproducible generation.",
    )

    parser.add_argument(
        "--background_dir",
        type=str,
        default=None,
        help="Directory containing background textures.",
    )

    args = parser.parse_args()

    build_text_dataset(
        output_root=args.output_root,
        text_source=args.text_source,
        prefix=args.prefix,
        max_pages=args.max_pages,
        seed=args.seed,
        background_dir=args.background_dir,
    )