from sqlmodel import Session, select
from uuid import UUID

from backend.app.models.inference import InferenceResult
from backend.app.models.image import Image


def create_inference_result(
    session: Session,
    image_id: UUID,
    extracted_text: str,
    annotations: list[dict],
    lang: str = "en",
):
    result = InferenceResult(
        image_id=image_id,
        extracted_text=extracted_text,
        annotations=annotations,
        lang=lang,
    )

    session.add(result)
    session.commit()
    session.refresh(result)

    return result

def get_predictions_by_user_id(session: Session, user_id: UUID):
    statement = (
        select(InferenceResult)
        .join(Image, InferenceResult.image_id == Image.id)
        .where(Image.user_id == user_id)
        .order_by(InferenceResult.created_at.desc())
    )

    return session.exec(statement).all()