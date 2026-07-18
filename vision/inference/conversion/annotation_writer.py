from typing import Any, Dict, List

from ..utils.file_utils import image_dimensions


def to_yolo_lines(prediction_result, image_path: str) -> str:
    """
    Serialise predictions as a YOLO-format string (normalised coordinates).
    Caller is responsible for writing to disk.
    """
    h, w = image_dimensions(image_path)
    lines = []

    for obj in prediction_result.object_prediction_list:
        class_id = obj.category.id
        x1, y1 = obj.bbox.minx, obj.bbox.miny
        x2, y2 = obj.bbox.maxx, obj.bbox.maxy

        cx = ((x1 + x2) / 2) / w
        cy = ((y1 + y2) / 2) / h
        bw = (x2 - x1) / w
        bh = (y2 - y1) / h

        lines.append(f"{class_id} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}")

    return "\n".join(lines)


def to_detections_json(prediction_result, image_path: str) -> List[Dict[str, Any]]:
    h, w = image_dimensions(image_path)
    return [
        {
            "class_id": int(obj.category.id),
            "x1": float(obj.bbox.minx) / w,
            "y1": float(obj.bbox.miny) / h,
            "x2": float(obj.bbox.maxx) / w,
            "y2": float(obj.bbox.maxy) / h,
        }
        for obj in prediction_result.object_prediction_list
    ]