from typing import List
from sqlmodel import Session
from uuid import UUID
from vision.inference.pipeline import pipeline, pipeline_batch
from backend.app.repositories.image_repository import (
    get_image_by_id,
    get_images_by_ids,
)
from backend.app.repositories.inference_repository import (
    create_inference_result,
    get_predictions_by_user_id,
    get_prediction_by_id,
    delete_prediction,
)
from backend.app.core.configs import InferenceConfig


def run_inference_service(session: Session, image_id: UUID, lang: str):
    """Reads the braille in a single previously-uploaded image."""
    image = get_image_by_id(session, image_id)
    if image is None:
        raise ValueError("Image not found")
    cfg = InferenceConfig.resolve_cfg(lang)
    output = pipeline(image_path=image.image_path, cfg=cfg)
    result = create_inference_result(
        session=session,
        image_id=image_id,
        extracted_text=output["extracted_text"],
        annotations=output["annotations"],
        lang=lang,
    )
    return {
        "id": result.id,
        "image_id": image_id,
        "extracted_text": result.extracted_text,
        "annotations": result.annotations,
        "created_at": result.created_at,
    }


def delete_prediction_service(session: Session, prediction_id: UUID, user_id: UUID):
    prediction = get_prediction_by_id(session, prediction_id)
    if prediction is None:
        raise ValueError("Prediction not found")
    image = get_image_by_id(session, prediction.image_id)
    if image is None or image.user_id != user_id:
        raise PermissionError("Not authorized to delete this prediction")
    delete_prediction(session=session, prediction=prediction)


def run_batch_inference_service(
    session: Session,
    image_ids: List[UUID],
    lang: str,
):
    """Reads the braille across multiple images, loading the model once.
    Raises ValueError if any image_id doesn't exist (caller should map this
    to a 404, same convention as run_inference_service).
    """
    images = get_images_by_ids(session, image_ids)
    found_ids = {image.id for image in images}
    missing = [str(i) for i in image_ids if i not in found_ids]
    if missing:
        raise ValueError(f"Image(s) not found: {', '.join(missing)}")
    # get_images_by_ids isn't guaranteed to preserve input order (e.g. if it's
    # backed by a plain `WHERE id IN (...)` query), so reorder to match what
    # the caller asked for. This matters because the mobile client zips these
    # results back up against its own locally-ordered list of scanned images.
    images_by_id = {image.id: image for image in images}
    ordered_images = [images_by_id[i] for i in image_ids]
    cfg = InferenceConfig.resolve_cfg(lang)
    outputs = pipeline_batch(
        image_paths=[image.image_path for image in ordered_images],
        cfg=cfg,
    )
    results = []
    for image, output in zip(ordered_images, outputs):
        result = create_inference_result(
            session=session,
            image_id=image.id,
            extracted_text=output["extracted_text"],
            annotations=output["annotations"],
            lang=lang,
        )
        results.append(
            {
                "id": result.id,
                "image_id": image.id,
                "extracted_text": result.extracted_text,
                "annotations": result.annotations,
                "created_at": result.created_at,
            }
        )
    return results


def get_prediction_history(session: Session, user_id: UUID):
    """Returns this user's server-side braille reading history, most
    recent first (see get_predictions_by_user_id's ORDER BY)."""
    return get_predictions_by_user_id(session=session, user_id=user_id)