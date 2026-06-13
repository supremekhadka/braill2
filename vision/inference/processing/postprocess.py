import numpy as np
import torch
from torchvision.ops import nms

def apply_global_nms(prediction_result, iou_threshold: float = 0.1) -> tuple:
    preds = prediction_result.object_prediction_list
    if not preds:
        return prediction_result, 0

    boxes = torch.tensor([p.bbox.to_xyxy() for p in preds], dtype=torch.float32)
    scores = torch.tensor([p.score.value for p in preds], dtype=torch.float32)
    keep = nms(boxes, scores, iou_threshold)
    n_removed = len(preds) - len(keep)
    prediction_result.object_prediction_list = [preds[i] for i in keep]
    return prediction_result, n_removed


def filter_area_outliers(prediction_result) -> tuple:
    preds = prediction_result.object_prediction_list

    if not preds:
        return prediction_result, 0

    areas = [
        (p.bbox.maxx - p.bbox.minx) *
        (p.bbox.maxy - p.bbox.miny)
        for p in preds
    ]

    q1, q3 = np.percentile(areas, [25, 75])
    iqr = q3 - q1

    adaptive_max = q3 + 1.5 * iqr
    max_area = min(adaptive_max, 2000)

    filtered = [
        p
        for p in preds
        if ((p.bbox.maxx - p.bbox.minx) *
            (p.bbox.maxy - p.bbox.miny)) <= max_area
    ]

    n_removed = len(preds) - len(filtered)

    prediction_result.object_prediction_list = filtered

    return prediction_result, n_removed
