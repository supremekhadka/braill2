from typing import Any, Dict, List

from .processing.sahi_inference import load_model, run_sliced_inference
from .conversion.annotation_writer import to_detections_json
from .utils.file_utils import load_label_map
from .conversion.text_construction import convert_detections_to_text
# from .processing.postprocess import filter_area_outliers
# from .processing.postprocess import mad_filter_area_outliers
from .processing.postprocess import apply_global_nms

DEFAULT_DEVICE = "cuda"


def pipeline(image_path, cfg: dict, device: str = DEFAULT_DEVICE) -> Dict[str, Any]:
    """Run inference on a single image.

    Thin wrapper around pipeline_batch so single and batch inference always
    share the exact same per-image logic.
    """
    return pipeline_batch([image_path], cfg, device)[0]


def pipeline_batch(
    image_paths: List[str], cfg: dict, device: str = DEFAULT_DEVICE
) -> List[Dict[str, Any]]:
    """Run inference on multiple images in one call.

    The model and label map are loaded exactly once and reused across every
    image in the batch, which is the whole point of batching (avoids
    reloading the model per image). Results are returned in the same order
    as image_paths.
    """
    model = load_model(
        cfg["model"],
        device,
        confidence_threshold=cfg["confidence"],
    )
    label_map = load_label_map(cfg["label_map"])

    results: List[Dict[str, Any]] = []

    for image_path in image_paths:
        pred = run_sliced_inference(
            model=model,
            image_path=image_path,
            slice_size=cfg["slice_size"],
            overlap=cfg["overlap"],
        )

        raw_detections = len(pred.object_prediction_list)
        n_area_removed = 0
        # n_removed = 0
        pred, n_removed = apply_global_nms(
            pred,
            iou_threshold=cfg["nms_iou"],
        )
        # pred, n_area_removed = mad_filter_area_outliers(pred, threshold=10)

        extracted_text = convert_detections_to_text(
            prediction_result=pred,
            label_map=label_map,
            confidence_threshold=cfg["confidence"],
        )
        annotations = to_detections_json(pred, image_path)

        results.append(
            {
                "extracted_text": extracted_text,
                "annotations": annotations,
                "raw_detections": raw_detections,
                "outliers_removed": n_area_removed,
                "nms_removed": n_removed,
            }
        )

    return results