from sahi import AutoDetectionModel
from sahi.predict import get_sliced_prediction


def load_model(model_path: str, device: str, confidence_threshold: float = 0.4) -> AutoDetectionModel:
    return AutoDetectionModel.from_pretrained(
        model_type="ultralytics",
        model_path=model_path,
        confidence_threshold=confidence_threshold,
        device=device,
    )


def run_sliced_inference(
    model: AutoDetectionModel,
    image_path: str,
    slice_size: int,
    overlap: float,
    postprocess_match_threshold: float = 0.5,
):
    return get_sliced_prediction(
        image=image_path,
        detection_model=model,
        slice_height=slice_size,
        slice_width=slice_size,
        overlap_height_ratio=overlap,
        overlap_width_ratio=overlap,
        postprocess_type="NMM",
        postprocess_match_metric="IOU",
        postprocess_match_threshold=postprocess_match_threshold,
        verbose=False,
    )
