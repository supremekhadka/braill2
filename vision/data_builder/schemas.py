from __future__ import annotations

from dataclasses import dataclass

@dataclass(frozen=True, slots=True)
class BBox:
    class_id: int
    cx: float
    cy: float
    w: float
    h: float

    @classmethod
    def from_corners(
        cls,
        class_id: int,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        img_w: int,
        img_h: int,
    ) -> "BBox":
        """Build a BBox from absolute pixel corners (x1, y1, x2, y2)."""
        width = x2 - x1
        height = y2 - y1
        cx = (x1 + width / 2) / img_w
        cy = (y1 + height / 2) / img_h
        w = width / img_w
        h = height / img_h
        return cls(class_id=class_id, cx=cx, cy=cy, w=w, h=h)

    @classmethod
    def from_absolute_center(
        cls,
        class_id: int,
        abs_cx: float,
        abs_cy: float,
        abs_w: float,
        abs_h: float,
        img_w: int,
        img_h: int,
    ) -> "BBox":
        """Build a BBox from absolute-pixel centre + size values."""
        return cls(
            class_id=class_id,
            cx=abs_cx / img_w,
            cy=abs_cy / img_h,
            w=abs_w / img_w,
            h=abs_h / img_h,
        )

    def to_corners_abs(self, img_w: int, img_h: int) -> tuple[float, float, float, float]:
        """Return (x1, y1, x2, y2) in absolute pixels."""
        abs_w = self.w * img_w
        abs_h = self.h * img_h
        abs_cx = self.cx * img_w
        abs_cy = self.cy * img_h
        return (
            abs_cx - abs_w / 2,
            abs_cy - abs_h / 2,
            abs_cx + abs_w / 2,
            abs_cy + abs_h / 2,
        )

    def is_valid(self) -> bool:
        """Return True when all values are in the expected range."""
        return (
            self.class_id >= 0
            and 0.0 <= self.cx <= 1.0
            and 0.0 <= self.cy <= 1.0
            and 0.0 < self.w <= 1.0
            and 0.0 < self.h <= 1.0
        )


@dataclass
class Sample:
    image_path: str
    label_path: str
    source: str
    annotations: list[BBox]

    def is_valid(self) -> bool:
        return bool(self.image_path) and bool(self.label_path)