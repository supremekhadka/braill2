import cv2
import numpy as np

from .file_utils import load_label_map

def _draw_detection(
    img,
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    label: str,
) -> None:
    cv2.rectangle(img, (x1, y1), (x2, y2), (0, 255, 0), 2)

    font_scale = min(0.35, max(0.15, (y2 - y1) / 135))
    (tw, th), _ = cv2.getTextSize(
        label,
        cv2.FONT_HERSHEY_SIMPLEX,
        font_scale,
        1,
    )

    cv2.rectangle(
        img,
        (x1, max(0, y1 - th - 6)),
        (x1 + tw, y1),
        (0, 255, 0),
        -1,
    )

    cv2.putText(
        img,
        label,
        (x1, max(15, y1 - 5)),
        cv2.FONT_HERSHEY_SIMPLEX,
        font_scale,
        (0, 0, 0),
        1,
        cv2.LINE_AA,
    )


def render_from_predictions(
    image_path: str,
    prediction_result,
    label_map_path: str,
) -> np.ndarray:
    img = cv2.imread(image_path)

    if img is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")

    label_map = load_label_map(label_map_path)

    for obj in prediction_result.object_prediction_list:
        x1, y1, x2, y2 = map(
            int,
            [
                obj.bbox.minx,
                obj.bbox.miny,
                obj.bbox.maxx,
                obj.bbox.maxy,
            ],
        )

        label = label_map.get(
            obj.category.id,
            str(obj.category.id),
        )

        _draw_detection(img, x1, y1, x2, y2, label)

    return img

def render_from_json(
    image_path: str,
    records: list[dict],
    label_map_path: str,
) -> np.ndarray:
    img = cv2.imread(image_path)
    h, w = img.shape[:2]

    if img is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")

    label_map = load_label_map(label_map_path)

    for r in records:
        label = label_map.get(
            r["class_id"],
            str(r["class_id"]),
        )

        _draw_detection(
            img,
            int(r["x1"] * w),
            int(r["y1"] * h),
            int(r["x2"] * w),
            int(r["y2"] * h),
            label,
        )

    return img