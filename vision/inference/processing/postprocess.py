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


# def filter_area_outliers(prediction_result) -> tuple:
#     preds = prediction_result.object_prediction_list

#     if not preds:
#         return prediction_result, 0

#     areas = [
#         (p.bbox.maxx - p.bbox.minx) *
#         (p.bbox.maxy - p.bbox.miny)
#         for p in preds
#     ]

#     q1, q3 = np.percentile(areas, [25, 75])
#     iqr = q3 - q1

#     adaptive_max = q3 + 1.5 * iqr
#     max_area = min(adaptive_max, 2000)

#     filtered = [
#         p
#         for p in preds
#         if ((p.bbox.maxx - p.bbox.minx) *
#             (p.bbox.maxy - p.bbox.miny)) <= max_area
#     ]

#     n_removed = len(preds) - len(filtered)

#     prediction_result.object_prediction_list = filtered

#     return prediction_result, n_removed

def mad_filter_area_outliers(prediction_result, threshold: float = 3.5) -> tuple:
    """
    Remove detections whose box width or height is an outlier relative to
    the median width/height, using Median Absolute Deviation (MAD).
    A box is removed if EITHER its width or its height is flagged.

    threshold: number of "modified z-score" units away from the median
               a point must be to be considered an outlier. 3.5 is the
               commonly cited default (Iglewicz & Hoaglin).
    """
    preds = prediction_result.object_prediction_list
    if not preds:
        return prediction_result, 0

    widths = np.array([p.bbox.maxx - p.bbox.minx for p in preds])
    heights = np.array([p.bbox.maxy - p.bbox.miny for p in preds])

    def mad_stats(values, name):
        median = np.median(values)
        abs_deviations = np.abs(values - median)
        mad = np.median(abs_deviations)

        if mad == 0:
            keep_mask = np.ones(len(values), dtype=bool)
            z_scores = np.zeros(len(values))
            max_allowed_deviation = 0.0
        else:
            z_scores = 0.6745 * abs_deviations / mad
            keep_mask = z_scores <= threshold
            max_allowed_deviation = threshold * mad / 0.6745

        print(f"--- {name} outlier filter stats ---")
        print(f"  n_detections:          {len(values)}")
        print(f"  median_{name}:          {median:.2f}")
        print(f"  MAD:                   {mad:.2f}")
        print(f"  threshold (z-score):   {threshold}")
        print(f"  max_allowed_deviation: {max_allowed_deviation:.2f} "
              f"(i.e. {name} must be within "
              f"[{median - max_allowed_deviation:.2f}, "
              f"{median + max_allowed_deviation:.2f}])")

        removed = ~keep_mask
        if removed.any():
            print(f"  outliers_removed:      {removed.sum()}")
            for v, dev, z in sorted(
                zip(values[removed], abs_deviations[removed], z_scores[removed]),
                key=lambda t: -t[2],
            ):
                print(f"    {name}={v:.2f}  deviation={dev:.2f}  z_score={z:.2f}")
        else:
            print("  outliers_removed:      0")
        print("-" * (len(name) + 34))

        return keep_mask

    width_keep = mad_stats(widths, "width")
    height_keep = mad_stats(heights, "height")

    # a box survives only if it's not an outlier on either dimension
    keep_mask = width_keep & height_keep

    filtered = [p for p, keep in zip(preds, keep_mask) if keep]
    n_removed = len(preds) - len(filtered)
    prediction_result.object_prediction_list = filtered
    return prediction_result, n_removed