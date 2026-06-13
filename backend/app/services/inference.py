from sqlmodel import Session
from uuid import UUID

from vision.inference.pipeline import pipeline
from backend.app.repositories.image_repository import get_image_by_id
from backend.app.repositories.inference_repository import create_inference_result, get_predictions_by_user_id
from backend.app.core.configs import InferenceConfig


def run_inference_service(
    session: Session,
    image_id: UUID,
    lang: str
):
    image = get_image_by_id(session, image_id)

    if image is None:
        raise ValueError("Image not found")

    cfg = InferenceConfig.resolve_cfg(lang)

    output = pipeline(
        image_path=image.image_path,
        cfg=cfg
    )

    result = create_inference_result(
        session=session,
        image_id=image_id,
        extracted_text=output["extracted_text"],
        annotations=output["annotations"],
        lang=lang,
    )

    return {
        "extracted_text": result.extracted_text,
        "annotations": result.annotations,
    }

def get_prediction_history(session: Session, user_id: UUID):
    return get_predictions_by_user_id(
            session=session,
            user_id=user_id
        )