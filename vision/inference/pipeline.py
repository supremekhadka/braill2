from typing import Any, Dict

from .processing.sahi_inference import load_model, run_sliced_inference
from .conversion.annotation_writer import to_detections_json
from .utils.file_utils import load_label_map
from .conversion.text_construction import convert_detections_to_text
from .processing.postprocess import filter_area_outliers, apply_global_nms


DEFAULT_DEVICE = "cuda"


def pipeline(image_path, cfg: dict, device: str = DEFAULT_DEVICE) -> Dict[str, Any]:
    model = load_model(
        cfg["model"],
        device,
        confidence_threshold=cfg["confidence"],
    )

    pred = run_sliced_inference(
        model=model,
        image_path=image_path,
        slice_size=cfg["slice_size"],
        overlap=cfg["overlap"],
    )

    raw_detections = len(pred.object_prediction_list)

    # pred, n_area_removed = filter_area_outliers(pred)

    pred, n_removed = apply_global_nms(
        pred,
        iou_threshold=cfg["nms_iou"],
    )

    n_area_removed = 0
    # n_removed = 0

    result = convert_detections_to_text(
        prediction_result=pred,
        label_map=load_label_map(cfg["label_map"]),
        confidence_threshold=cfg["confidence"],
    )

    annotations = to_detections_json(pred)

    return {
        "extracted_text": result,
        "annotations": annotations,
        "raw_detections": raw_detections,
        "outliers_removed": n_area_removed,
        "nms_removed": n_removed
    }