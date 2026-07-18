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
        background_dir: str | None = None,
        seed: int | None = None,
        supersample: int = 1,   # render at N x target res, then downsample
    ) -> None:
        if seed is not None:
            random.seed(seed)
            np.random.seed(seed)

        self.output_size = img_size                     # final delivered resolution
        self.supersample = max(1, supersample)
        self.img_size = (                                # working/render resolution
            img_size[0] * self.supersample,
            img_size[1] * self.supersample,
        )

        if scale is None:
            if random.random() < small_scale_ratio:
                self.scale = random.uniform(3.2, 4.0)
            else:
                self.scale = random.uniform(4.5, 5.5)
        else:
            self.scale = scale

        # scale is "working pixels per mm-unit"; multiplying by supersample
        # here makes every downstream pixel quantity render at full
        # supersampled resolution automatically.
        self.scale *= self.supersample

        self.bbox_pad = bbox_pad_mm * self.scale
        self.background_dir = background_dir

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

    def generate_wear_map(self) -> np.ndarray:
        """Smooth 0..1 field: 1 = heavily worn/rubbed area, 0 = pristine."""
        small = np.random.uniform(0, 1, (self.img_size[0] // 40, self.img_size[1] // 40))
        wear = cv2.resize(small.astype(np.float32), (self.img_size[1], self.img_size[0]),
                        interpolation=cv2.INTER_CUBIC)
        wear = cv2.GaussianBlur(wear, (0, 0), sigmaX=self.scale * 8)
        wear = (wear - wear.min()) / (wear.max() - wear.min() + 1e-6)
        return wear ** 3   # bias toward mostly-pristine with a few worn patches

    def degrade_bump(self, bump: np.ndarray, mode: str) -> np.ndarray:
        """Randomly wear, smear, or tear a single dot's kernel."""
        h, w = bump.shape
        if mode == "worn":
            return bump * random.uniform(0.5, 0.8)

        if mode == "smear":
            length = random.randint(2, max(2, int(w * 0.2)))
            angle = random.uniform(0, 360)
            kernel = np.zeros((length, length), dtype=np.float32)
            kernel[length // 2, :] = 1.0
            M = cv2.getRotationMatrix2D((length / 2, length / 2), angle, 1)
            kernel = cv2.warpAffine(kernel, M, (length, length))
            kernel /= kernel.sum() + 1e-6
            return cv2.filter2D(bump, -1, kernel)

        if mode == "torn":
            low = np.random.normal(0, 1, (10, 10)).astype(np.float32)
            blob = cv2.resize(low, (w, h), interpolation=cv2.INTER_CUBIC)
            blob = cv2.GaussianBlur(blob, (0, 0), sigmaX=w * 0.15)
            blob = (blob - blob.min()) / (blob.max() - blob.min() + 1e-6)
            thresh = 0.9
            mask = np.clip((blob - thresh) / (1 - thresh), 0, 1)
            return bump * mask

        return bump

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

    def create_embossed_bump(
        self,
        radius: float,
        top_ratio: float = 0.6,
        falloff_power: float = 0.75,
        height_scale: float = 0.45,
        upsample: int = 2,
    ) -> np.ndarray:
        radius = radius - 0.4
        falloff_power = falloff_power + random.uniform(-0.1, 0.1)
        edge_roughness = random.uniform(0.05, 0.2)
        size = int(radius * 4)
        if size % 2 == 0:
            size += 1

        hi = size * upsample
        center = hi / 2.0 - 0.5

        radius_hi = radius * upsample
        top_radius_hi = radius_hi * top_ratio

        yy, xx = np.mgrid[0:hi, 0:hi].astype(np.float32)
        d = np.sqrt((yy - center) ** 2 + (xx - center) ** 2)
        theta = np.arctan2(yy - center, xx - center)

        # Perturb the radius as a function of angle using multi-octave
        # circular (value) noise rather than a few clean sine harmonics.
        # A handful of low-k cosines always looks "flowery" (regular,
        # periodic lobes); summing several octaves of randomly sampled,
        # linearly-interpolated noise around the circle gives an
        # irregular, torn-paper-like edge instead — each octave adds
        # detail at its own angular frequency with an independent random
        # phase, so nothing lines up into a repeating pattern.
        theta_norm = (theta + np.pi) / (2 * np.pi)  # wrap to [0, 1)

        n_octaves = random.randint(3, 5)
        base_points = random.randint(4, 8)  # control points for octave 0
        wobble = np.zeros_like(theta)
        amp_total = 0.0
        for o in range(n_octaves):
            n_pts = max(3, int(base_points * (2 ** o)))

            ctrl = np.random.uniform(-1, 1, n_pts + 1)
            ctrl[-1] = ctrl[0]
            xs = np.linspace(0.0, 1.0, n_pts + 1)
            octave_noise = np.interp(theta_norm, xs, ctrl)
            amp = 1.0 / (o + 1) ** 1.1  # higher octaves add fine detail, weighted down but not negligible
            wobble += octave_noise * amp
            amp_total += amp
        wobble /= amp_total
        radius_scale = 1.0 + wobble * edge_roughness

        d_eff = d / radius_scale

        kernel_hi = np.zeros((hi, hi), dtype=np.float32)
        kernel_hi[d_eff <= top_radius_hi] = 1.0

        edge_mask = (d_eff > top_radius_hi) & (d_eff < radius_hi)
        span = max(radius_hi - top_radius_hi, 1e-6)
        t = np.clip((d_eff - top_radius_hi) / span, 0.0, 1.0)
        kernel_hi[edge_mask] = np.cos(t[edge_mask] * (np.pi / 2)) ** falloff_power

        kernel = cv2.resize(kernel_hi, (size, size), interpolation=cv2.INTER_AREA)
        return kernel * height_scale

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
        texture = np.full(self.img_size, 1.01, dtype=np.float32)
        grain = np.random.normal(0.0025, 0.0275, self.img_size)
        small_noise = np.random.normal(
            0, 0.08, (self.img_size[0] // 20, self.img_size[1] // 20)
        )
        clouds = cv2.resize(
            small_noise, (self.img_size[1], self.img_size[0]),
            interpolation=cv2.INTER_CUBIC,
        )
        clouds = cv2.GaussianBlur(clouds, (15, 15), 0)
        return texture + grain + (clouds * 0.005)

    def apply_color_tint(self, img: np.ndarray) -> np.ndarray:
        """Apply a random warm/cool colour tint to a 3-channel float32 BGR image."""
        temp = random.uniform(-1.1, 1.0)
        brightness = random.uniform(0.85, 1.0)

        if temp > 0:
            b_mult = 1.0 - (temp * 0.45)
            g_mult = 1.0 - (temp * 0.20)
            r_mult = 1.0
        else:
            b_mult = 1.0
            g_mult = 1.0 - (abs(temp) * 0.05)
            r_mult = 1.0 - (abs(temp) * 0.20)

        img[:, :, 0] *= r_mult * brightness
        img[:, :, 1] *= g_mult * brightness
        img[:, :, 2] *= b_mult * brightness
        return img

    def load_random_background(self, w: int, h: int) -> np.ndarray:
        """
        Return an (h, w, 3) float32 BGR image in [0, 1] used as page backing
        where the perspective warp exposes the canvas edges. Picks a random
        image from self.background_dir if available, else solid black.
        """
        if self.background_dir:
            exts = (".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp")
            try:
                candidates = [
                    os.path.join(self.background_dir, f)
                    for f in os.listdir(self.background_dir)
                    if f.lower().endswith(exts)
                ]
            except (FileNotFoundError, NotADirectoryError):
                candidates = []

            random.shuffle(candidates)
            for path in candidates:
                bg = cv2.imread(path, cv2.IMREAD_COLOR)
                if bg is not None:
                    bg = cv2.resize(bg, (w, h), interpolation=cv2.INTER_LINEAR)
                    return bg.astype(np.float32) / 255.0

        return np.zeros((h, w, 3), dtype=np.float32)

    def apply_perspective_skew(
        self,
        img: np.ndarray,
        max_skew_px: int = 180,
        max_rot_deg: float = 2.5,
    ) -> tuple[np.ndarray, np.ndarray]:
        """
        Apply a random 3-D perspective distortion or 2-D rotation.
        Returns (warped_image, perspective_matrix); the homography is used
        downstream to warp annotation corners.
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

        # Warp with a transparent border, then fill exposed corners with a
        # real background image (or black) instead of smeared page.
        warped = cv2.warpPerspective(
            img, M, (w, h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=(0, 0, 0),
        )

        mask = cv2.warpPerspective(
            np.ones((h, w), dtype=np.float32), M, (w, h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_CONSTANT,
            borderValue=0,
        )
        mask = np.clip(mask, 0.0, 1.0)[..., None]

        background = self.load_random_background(w, h)
        warped = warped * mask + background * (1.0 - mask)

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

    def generate_light_gradient(self, azimuth_deg: float, strength: float = 0.12) -> np.ndarray:
        """
        Linear gradient across the image aligned with the light's azimuth.
        The side facing the light is brighter, falling off to the opposite side.
        """
        h, w = self.img_size
        y = np.linspace(-1.0, 1.0, h, dtype=np.float32)
        x = np.linspace(-1.0, 1.0, w, dtype=np.float32)
        xv, yv = np.meshgrid(x, y)

        az_rad = np.radians(azimuth_deg)
        ux = np.cos(az_rad)
        uy = np.sin(az_rad)

        gradient = xv * ux + yv * uy

        # Normalize by the true achievable peak for this azimuth so gradient
        # strength is consistent across azimuths.
        norm = max(abs(ux) + abs(uy), 1e-6)
        gradient = gradient / norm

        return gradient * strength

    def generate_page(
        self,
        allowed_chars: list[int] | None = None,
        margin_mm: float = 20.0,
        space_prob: float = 0.15,
        apply_skew: bool = True,
    ) -> tuple[np.ndarray, list[str]]:
        if allowed_chars is None:
            allowed_chars = list(range(63))

        recto_h = np.zeros(self.img_size, dtype=np.float32)
        verso_h = np.zeros(self.img_size, dtype=np.float32)

        # Template bumps purely to fix kernel size/offset for array indexing;
        # the actual base shape used for stamping is regenerated per cell
        # below so every dot gets its own random edge roughness.
        _bump_template = self.create_embossed_bump(self.dot_rad)
        bh, bw = _bump_template.shape
        offset = bh // 2

        verso_dot_scale = random.uniform(0.75, 0.9)  # verso (back-side) dots render smaller than recto
        _verso_bump_template = self.create_embossed_bump(self.dot_rad * verso_dot_scale)
        verso_bh, verso_bw = _verso_bump_template.shape
        verso_offset = verso_bh // 2

        margin = int(margin_mm * self.scale)
        cols = int((self.img_size[1] - 2 * margin) // self.px_cell_w)
        rows = int((self.img_size[0] - 2 * margin) // self.px_line_h)

        # Raw bboxes in absolute pixel coords before perspective warp
        raw_bboxes: list[tuple[int, float, float, float, float]] = []

        # Randomize how much degradation this page gets: each page draws
        # its own smear/worn/torn/pristine proportions, so some pages come
        # out mostly pristine and others heavily degraded.
        recto_smear_p = random.uniform(0.1, 0.6)
        recto_worn_p = min(recto_smear_p + random.uniform(0.1, 0.4), 1.0)

        verso_torn_p = random.uniform(0.0, 0.15)
        verso_smear_p = min(verso_torn_p + random.uniform(0.1, 0.4), 1.0)
        verso_worn_p = min(verso_smear_p + random.uniform(0.1, 0.4), 1.0)

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

                    # Fresh base bump per cell so each character's dots get
                    # their own random edge roughness, then one shared
                    # degradation kernel on top so the cell wears as a unit.
                    top_ratio = random.uniform(0.1, 0.45) if self.scale >= 10 else random.uniform(0.5, 0.7)
                    bump = self.create_embossed_bump(self.dot_rad, top_ratio=top_ratio, falloff_power=random.uniform(0.6, 0.8))
                    cell_roll = random.random()
                    if cell_roll < recto_smear_p:
                        cell_bump = self.degrade_bump(bump, "smear")
                    elif cell_roll < recto_worn_p:
                        cell_bump = self.degrade_bump(bump, "worn")
                    else:
                        cell_bump = bump

                    for i, bit in enumerate(bit_str):
                        if bit == "1":
                            jx = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                            jy = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                            dx = (i // 3) * self.px_h_dot + jx
                            dy = (i % 3) * self.px_v_dot + jy
                            y_c, x_c = int(py + dy), int(px + dx)

                            dot_bump = cell_bump

                            y1_b = y_c - offset; y2_b = y_c + offset + 1
                            x1_b = x_c - offset; x2_b = x_c + offset + 1
                            if (0 <= y1_b and y2_b < self.img_size[0]
                                    and 0 <= x1_b and x2_b < self.img_size[1]):
                                recto_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                                    recto_h[y1_b:y2_b, x1_b:x2_b], dot_bump
                                )

                # Verso
                if random.random() > space_prob:
                    v_char_id = int(np.random.choice(allowed_chars))
                    v_bit_str = self.id_to_bits(v_char_id)
                    vx = px + self.px_h_dot / 2
                    vy = py + self.px_v_dot / 2

                    verso_top_ratio = random.uniform(0.1, 0.45) if self.scale >= 10 else random.uniform(0.5, 0.7)
                    verso_bump = self.create_embossed_bump(self.dot_rad * verso_dot_scale, top_ratio=verso_top_ratio, falloff_power=random.uniform(0.6, 0.8))
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
                        if bit == "1":
                            jx = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                            jy = random.uniform(-0.02, 0.02) * self.scale if random.random() < 0.5 else 0.0
                            dx = (i // 3) * self.px_h_dot + jx
                            dy = (i % 3) * self.px_v_dot + jy
                            y_c, x_c = int(vy + dy), int(vx + dx)

                            dot_bump = verso_cell_bump

                            y1_b = y_c - verso_offset; y2_b = y_c + verso_offset + 1
                            x1_b = x_c - verso_offset; x2_b = x_c + verso_offset + 1
                            if (
                                0 <= y1_b and y2_b < self.img_size[0]
                                and 0 <= x1_b and x2_b < self.img_size[1]
                            ):
                                verso_h[y1_b:y2_b, x1_b:x2_b] = np.maximum(
                                    verso_h[y1_b:y2_b, x1_b:x2_b], dot_bump
                                )

        wear_map = self.generate_wear_map()
        wear_strength = .5
        recto_h *= (1.0 - wear_map * wear_strength)
        total_h = recto_h * 1.0 - verso_h * 0.8
        blur_px = 1
        total_h = cv2.GaussianBlur(total_h, (blur_px, blur_px), 0)

        light_azimuth   = random.uniform(205, 335)
        light_elevation = random.uniform(0, 45)
        light_intensity = random.uniform(0.25, 0.55)

        shading = self.calculate_lighting(
            total_h,
            azimuth_deg=light_azimuth,
            elevation_deg=light_elevation,
            intensity=light_intensity,
        )

        # Trailing shadow cast by recto dots opposite to the light source
        shadow_dist = 0.9 * self.scale
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

        light_gradient = self.generate_light_gradient(light_azimuth, strength=random.uniform(0.15, 0.25))

        verso_darkness_factor = random.uniform(0.15, 0.35)
        final = self.generate_paper_texture() + shading + light_gradient - (verso_h * verso_darkness_factor)
        final = self.apply_vignette(final, strength=0.25)

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
            if M is not None:
                pts = np.float32(
                    [[x1, y1], [x2, y1], [x2, y2], [x1, y2]]
                ).reshape(-1, 1, 2)
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
            yolo_annotations.append(
                f"{char_id} {xc:.6f} {yc:.6f} {w / img_w:.6f} {h / img_h:.6f}"
            )

        final_uint8 = (np.clip(final_bgr, 0, 1) * 255).astype(np.uint8)

        if self.supersample > 1:
            # Area-based downsample gives the embossed dots a smooth,
            # physically pressed look instead of jagged/aliased edges.
            final_uint8 = cv2.resize(
                final_uint8,
                (self.output_size[1], self.output_size[0]),
                interpolation=cv2.INTER_AREA,
            )

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
    seed: int | None = None,
    background_dir: str | None = None,
    **generator_kwargs,
) -> list[Sample]:
    if generator is None:
        # seed here (rather than relying on caller-set global RNG state) is
        # what makes build() reproducible end-to-end: same seed + same
        # num_samples -> same images + same annotations.
        generator = BrailleGenerator(seed=seed, background_dir=background_dir, **generator_kwargs)

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


def build_multiscale(
    output_root: str,
    num_samples: int = 100,
    prefix: str = "SYN",
    scale_min: float = 3.5,
    scale_max: float = 15.0,
    seed: int | None = None,
    background_dir: str | None = None,
    **generator_kwargs,
) -> list[Sample]:
    """
    Like build(), but instead of each page drawing its scale from the
    class's built-in small/large probabilistic split (small_scale_ratio),
    scales are spread uniformly across [scale_min, scale_max] via
    np.linspace so every sample count gets even coverage of the range —
    no clumping and no gaps at the ends, which is what you'd get from
    np.random.uniform for small num_samples. The linspace array is then
    shuffled once so scale doesn't correlate with output file order.

    Seed is applied once up front (rather than per-BrailleGenerator
    instance) so the whole run consumes one continuous RNG stream and
    stays reproducible end-to-end; each per-sample BrailleGenerator below
    is constructed with seed=None so it doesn't reset that stream.
    """
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed)

    scales = np.linspace(scale_min, scale_max, num_samples)
    np.random.shuffle(scales)

    generator_kwargs.pop("scale", None)  # explicit per-sample scale below always wins

    images_out = os.path.join(output_root, "images")
    labels_out = os.path.join(output_root, "labels")
    os.makedirs(images_out, exist_ok=True)
    os.makedirs(labels_out, exist_ok=True)

    samples: list[Sample] = []
    pad = len(str(num_samples))
    milestone = max(1, num_samples // 10)

    for i, scale in enumerate(scales):
        generator = BrailleGenerator(
            scale=float(scale),
            background_dir=background_dir,
            seed=None,
            **generator_kwargs,
        )
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
                annotations=boxes,
            )
        )

        if (i + 1) % milestone == 0 or (i + 1) == num_samples:
            print(f"[synthetic] {i + 1}/{num_samples} samples generated "
                  f"(scale={scale:.2f})")

    print(f"[synthetic] Done (multiscale {scale_min}-{scale_max}): {output_root}")
    return samples