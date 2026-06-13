from __future__ import annotations

import os
import random

import cv2
import numpy as np

from ..schemas import BBox, Sample
from ..file_utils import write_label_file


class BrailleGenerator:
    def __init__(
        self,
        img_size: tuple[int, int] = (1448, 1024),
        scale: float | None = None,
        small_scale_ratio: float = 0.35,
        bbox_pad_mm: float = 0.25,
    ) -> None:
        self.img_size = img_size
        self.scale = scale
        if scale is None:
            if random.random() < small_scale_ratio:
                self.scale = random.uniform(3.2, 4.0)   # ~15 px cell width
            else:
                self.scale = random.uniform(4.5, 5.5)   # ~22–30 px cell width
        else:
            self.scale = scale
        self.bbox_pad = bbox_pad_mm * self.scale

        # Standard Marburg Medium dimensions (mm to pixels)
        self.dot_rad   = (1.5 / 2) * self.scale
        self.px_h_dot  = 2.5 * self.scale   
        self.px_v_dot  = 2.5 * self.scale   
        self.px_cell_w = 6.0 * self.scale   
        self.px_line_h = 10.0 * self.scale  

    def id_to_bits(self, char_id: int) -> str:
        """Convert a 0-based character index to a 6-bit Braille dot string."""
        char_id = max(0, min(62, char_id))
        binary = format(char_id + 1, "06b")
        return binary[::-1]  # LSB first: dot 1 at index 0

    def create_soft_bump(self, radius: float) -> np.ndarray:
        """Return a cosine-shaped height kernel for a single Braille dot."""
        size = int(radius * 4)
        if size % 2 == 0:
            size += 1
        kernel = np.zeros((size, size), dtype=np.float32)
        center = size // 2
        for i in range(size):
            for j in range(size):
                d = np.sqrt((i - center) ** 2 + (j - center) ** 2)
                if d < radius:
                    kernel[i, j] = np.cos(min(1.0, d / radius) * (np.pi / 2)) ** 1.4
        return kernel

    def apply_vignette(self, img: np.ndarray, strength: float = 0.2) -> np.ndarray:
        """Darken the edges of a 2-D float32 height map."""
        rows, cols = img.shape[:2]
        kx = cv2.getGaussianKernel(cols, cols / 2)
        ky = cv2.getGaussianKernel(rows, rows / 2)
        vignette = ky * kx.T
        vignette = vignette / vignette.max()
        return img * ((1 - strength) + strength * vignette)

    def generate_paper_texture(self) -> np.ndarray:
        """Return a float32 2-D array simulating paper grain and cloud noise."""
        texture = np.full(self.img_size, 0.99, dtype=np.float32)
        grain = np.random.normal(0, 0.035, self.img_size)
        small_noise = np.random.normal(
            0, 0.08, (self.img_size[0] // 20, self.img_size[1] // 20)
        )
        clouds = cv2.resize(
            small_noise, (self.img_size[1], self.img_size[0]),
            interpolation=cv2.INTER_CUBIC,
        )
        clouds = cv2.GaussianBlur(clouds, (15, 15), 0)
        return texture + grain + (clouds * 0.001)

    def apply_color_tint(self, img: np.ndarray) -> np.ndarray:
        """
        Apply a random warm/cool colour tint to a 3-channel float32 BGR image.

        Temperature ranges from -1.0 (cool) to +1.0 (warm).
        """
        temp = random.uniform(-1.0, 1.0)
        brightness = random.uniform(0.85, 1.0)

        if temp > 0:  # warm: attenuate blue and green slightly
            b_mult = 1.0 - (temp * 0.25)
            g_mult = 1.0 - (temp * 0.10)
            r_mult = 1.0
        else:          # cool: attenuate red and green slightly
            b_mult = 1.0
            g_mult = 1.0 - (abs(temp) * 0.05)
            r_mult = 1.0 - (abs(temp) * 0.20)

        img[:, :, 0] *= b_mult * brightness
        img[:, :, 1] *= g_mult * brightness
        img[:, :, 2] *= r_mult * brightness
        return img

    def apply_perspective_skew(
        self,
        img: np.ndarray,
        max_skew_px: int = 180,
        max_rot_deg: float = 2.5,
    ) -> tuple[np.ndarray, np.ndarray]:
        """
        Apply a random 3-D perspective distortion or 2-D rotation.

        Returns
        (warped_image, perspective_matrix)
            The 3x3 homography is used downstream to warp annotation corners.
        """
        h, w = img.shape[:2]
        skew_factor = max_skew_px * (self.scale / 10)

        src_pts = np.float32([[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1]])
        dst_pts = src_pts.copy()

        style = random.choice(["3d_pitch", "3d_yaw", "3d_combined", "2d_rotate"])

        if style == "3d_pitch":
            tilt = random.uniform(skew_factor * 0.2, skew_factor * 2.5)
            if random.choice([True, False]):
                dst_pts[0][0] += tilt; dst_pts[1][0] -= tilt
                dst_pts[0][1] += tilt; dst_pts[1][1] += tilt
            else:
                dst_pts[2][0] += tilt; dst_pts[3][0] -= tilt
                dst_pts[2][1] -= tilt; dst_pts[3][1] -= tilt

        elif style == "3d_yaw":
            tilt = random.uniform(skew_factor * 0.2, skew_factor * 2.5)
            if random.choice([True, False]):
                dst_pts[0][1] += tilt; dst_pts[2][1] -= tilt
                dst_pts[0][0] += tilt; dst_pts[2][0] += tilt
            else:
                dst_pts[1][1] += tilt; dst_pts[3][1] -= tilt
                dst_pts[1][0] -= tilt; dst_pts[3][0] -= tilt

        elif style == "3d_combined":
            px = random.uniform(skew_factor * 0.5, skew_factor * 2.0)
            py = random.uniform(skew_factor * 0.5, skew_factor * 2.0)
            corner = random.choice([0, 1, 2, 3])
            if corner == 0:
                dst_pts[0][0] += px; dst_pts[0][1] += py
                dst_pts[1][1] += py * 0.6; dst_pts[2][0] += px * 0.6
            elif corner == 1:
                dst_pts[1][0] -= px; dst_pts[1][1] += py
                dst_pts[0][1] += py * 0.6; dst_pts[3][0] -= px * 0.6
            elif corner == 2:
                dst_pts[2][0] += px; dst_pts[2][1] -= py
                dst_pts[0][0] += px * 0.6; dst_pts[3][1] -= py * 0.6
            else:
                dst_pts[3][0] -= px; dst_pts[3][1] -= py
                dst_pts[1][0] -= px * 0.6; dst_pts[2][1] -= py * 0.6

        elif style == "2d_rotate":
            angle_rad = np.radians(random.uniform(-max_rot_deg, max_rot_deg))
            cx, cy = w / 2, h / 2
            for i in range(4):
                x, y = src_pts[i]
                rx = cx + (x - cx) * np.cos(angle_rad) - (y - cy) * np.sin(angle_rad)
                ry = cy + (x - cx) * np.sin(angle_rad) + (y - cy) * np.cos(angle_rad)
                dst_pts[i] = [rx, ry]

        M = cv2.getPerspectiveTransform(src_pts, dst_pts)
        warped = cv2.warpPerspective(
            img, M, (w, h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE,
        )
        return warped, M

    def calculate_lighting(
        self,
        total_h: np.ndarray,
        azimuth_deg: float = 225.0,
        elevation_deg: float = 45.0,
        intensity: float = 0.3,
    ) -> np.ndarray:
        """Compute a diffuse-lighting shading layer from a height map."""
        dzdx = cv2.Sobel(total_h, cv2.CV_32F, 1, 0, ksize=3)
        dzdy = cv2.Sobel(total_h, cv2.CV_32F, 0, 1, ksize=3)

        az = np.radians(azimuth_deg)
        el = np.radians(elevation_deg)
        L = np.array(
            [np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)],
            dtype=np.float32,
        )

        mag = np.sqrt(dzdx ** 2 + dzdy ** 2 + 1)
        nx, ny, nz = -dzdx / mag, -dzdy / mag, 1.0 / mag

        diffuse = nx * L[0] + ny * L[1] + nz * L[2]
        return (diffuse - 1.0) * intensity

    def generate_page(
        self,
        allowed_chars: list[int] | None = None,
        margin_mm: float = 20.0,
        space_prob: float = 0.35,
        apply_skew: bool = True,
    ) -> tuple[np.ndarray, list[str]]:
        if allowed_chars is None:
            allowed_chars = list(range(63))

        recto_h = np.zeros(self.img_size, dtype=np.float32)
        verso_h = np.zeros(self.img_size, dtype=np.float32)

        bump = self.create_soft_bump(self.dot_rad)
        bh, bw = bump.shape
        offset = bh // 2

        margin = int(margin_mm * self.scale)
        cols = int((self.img_size[1] - 2 * margin) // self.px_cell_w)
        rows = int((self.img_size[0] - 2 * margin) // self.px_line_h)

        # Raw bboxes in absolute pixel coords before perspective warp
        raw_bboxes: list[tuple[int, float, float, float, float]] = []

        for r in range(rows):
            for c in range(cols):
                px = margin + c * self.px_cell_w
                py = margin + r * self.px_line_h

                # Recto
                if random.random() > space_prob:
                    char_id = int(np.random.choice(allowed_chars))
                    bit_str = self.id_to_bits(char_id)

                    x1 = px - self.dot_rad - self.bbox_pad
                    y1 = py - self.dot_rad - self.bbox_pad
                    x2 = px + self.px_h_dot + self.dot_rad + self.bbox_pad
                    y2 = py + 2 * self.px_v_dot + self.dot_rad + self.bbox_pad
                    raw_bboxes.append((char_id, x1, y1, x2, y2))

                    for i, bit in enumerate(bit_str):
                        if bit == "1":
                            jx = random.uniform(-0.05, 0.05) * self.scale
                            jy = random.uniform(-0.05, 0.05) * self.scale
                            dx = (i // 3) * self.px_h_dot + jx
                            dy = (i % 3) * self.px_v_dot + jy
                            y_c, x_c = int(py + dy), int(px + dx)

                            y1_b = y_c - offset; y2_b = y_c + offset + 1
                            x1_b = x_c - offset; x2_b = x_c + offset + 1
                            if (
                                0 <= y1_b and y2_b < self.img_size[0]
                                and 0 <= x1_b and x2_b < self.img_size[1]
                            ):
                                recto_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                                    recto_h[y1_b:y2_b, x1_b:x2_b], bump
                                )

                # Verso
                if random.random() > space_prob:
                    v_char_id = int(np.random.choice(allowed_chars))
                    v_bit_str = self.id_to_bits(v_char_id)
                    vx = px + self.px_cell_w / 2
                    vy = py + self.px_line_h / 2

                    for i, bit in enumerate(v_bit_str):
                        if bit == "1":
                            dx = (i // 3) * self.px_h_dot
                            dy = (i % 3) * self.px_v_dot
                            y_c, x_c = int(vy + dy), int(vx + dx)

                            y1_b = y_c - offset; y2_b = y_c + offset + 1
                            x1_b = x_c - offset; x2_b = x_c + offset + 1
                            if (
                                0 <= y1_b and y2_b < self.img_size[0]
                                and 0 <= x1_b and x2_b < self.img_size[1]
                            ):
                                verso_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                                    verso_h[y1_b:y2_b, x1_b:x2_b], bump
                                )

        total_h = recto_h * 1.0 - verso_h * 0.40
        total_h = cv2.GaussianBlur(total_h, (5, 5), 0)

        # Randomised lighting parameters
        light_azimuth   = random.uniform(200, 340)   # degrees
        light_elevation = random.uniform(15, 55)      # degrees
        light_intensity = random.uniform(0.15, 0.5)

        shading = self.calculate_lighting(
            total_h,
            azimuth_deg=light_azimuth,
            elevation_deg=light_elevation,
            intensity=light_intensity,
        )

        # Trailing shadow cast by recto dots opposite to the light source
        shadow_dist = 1.2 * self.scale
        az_rad = np.radians(light_azimuth)
        dx_s = -np.cos(az_rad) * shadow_dist
        dy_s = -np.sin(az_rad) * shadow_dist

        M_shadow = np.float32([[1, 0, dx_s], [0, 1, dy_s]])
        recto_shadow = cv2.warpAffine(
            recto_h, M_shadow, (self.img_size[1], self.img_size[0])
        )

        blur_size = int(self.scale * 2.5)
        if blur_size % 2 == 0:
            blur_size += 1
        recto_shadow = cv2.GaussianBlur(recto_shadow, (blur_size, blur_size), 0)
        # Mask out the bump itself so the shadow only falls on bare paper
        recto_shadow = np.clip(recto_shadow - recto_h, 0, 1)

        shadow_intensity = min(light_intensity * random.uniform(0.3, 0.6), 0.15)
        shading -= recto_shadow * shadow_intensity

        final = self.generate_paper_texture() + shading
        final = self.apply_vignette(final, strength=0.25)

        # Expand grayscale height map to 3-channel BGR for colour tinting
        final_bgr = np.stack([final, final, final], axis=-1)
        final_bgr = self.apply_color_tint(final_bgr)

        M = None
        if apply_skew:
            final_bgr, M = self.apply_perspective_skew(
                final_bgr, max_skew_px=80, max_rot_deg=2.5
            )

        img_h, img_w = final_bgr.shape[:2]
        yolo_annotations: list[str] = []

        for char_id, x1, y1, x2, y2 in raw_bboxes:
            # Warp the four corners of the raw bbox through the homography
            if M is not None:
                pts = np.float32(
                    [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
                ).reshape(-1, 1, 2)
                warped_pts = cv2.perspectiveTransform(pts, M)
                x1 = float(warped_pts[:, 0, 0].min())
                y1 = float(warped_pts[:, 0, 1].min())
                x2 = float(warped_pts[:, 0, 0].max())
                y2 = float(warped_pts[:, 0, 1].max())

            # Clip to image boundary
            x1, x2 = max(0.0, x1), min(float(img_w), x2)
            y1, y2 = max(0.0, y1), min(float(img_h), y2)

            w = x2 - x1
            h = y2 - y1
            if w <= 0 or h <= 0:
                continue

            xc = (x1 + w / 2) / img_w
            yc = (y1 + h / 2) / img_h
            yolo_annotations.append(
                f"{char_id} {xc:.6f} {yc:.6f} {w / img_w:.6f} {h / img_h:.6f}"
            )

        final_uint8 = (np.clip(final_bgr, 0, 1) * 255).astype(np.uint8)
        return final_uint8, yolo_annotations

def _parse_yolo_strings(annotation_strings: list[str]) -> list[BBox]:
    """Convert BrailleGenerator's raw string output into canonical BBox objects."""
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


def build(
    output_root: str,
    num_samples: int = 100,
    prefix: str = "SYN",
    generator: BrailleGenerator | None = None,
    **generator_kwargs,
) -> list[Sample]:
    if generator is None:
        generator = BrailleGenerator(**generator_kwargs)

    images_out = os.path.join(output_root, "images")
    labels_out = os.path.join(output_root, "labels")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    samples: list[Sample] = []
    pad = len(str(num_samples))
    milestone = max(1, num_samples // 10)

    for i in range(num_samples):
        img_bgr, annotation_strings = generator.generate_page()

        base_name = f"{prefix}_{i:0{pad}d}"
        dst_img = os.path.join(images_out, f"{base_name}.jpg")
        dst_lbl = os.path.join(labels_out, f"{base_name}.txt")

        cv2.imwrite(dst_img, img_bgr)

        boxes = _parse_yolo_strings(annotation_strings)
        write_label_file(boxes, dst_lbl)

        samples.append(
            Sample(
                image_path=dst_img,
                label_path=dst_lbl,
                source="synthetic",
                annotations=boxes
            )
        )

        if (i + 1) % milestone == 0 or (i + 1) == num_samples:
            print(f"[synthetic] {i + 1}/{num_samples} samples generated")

    print(f"[synthetic] Done: {output_root}")
    return samples