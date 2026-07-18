from typing import List
from sqlmodel import Session, select
from uuid import UUID

from backend.app.models.image import Image

def get_image_by_id(session: Session, image_id: UUID):
    statement = select(Image).where(Image.id == image_id)
    return session.exec(statement).first()

def get_images_by_ids(session, image_ids: List[UUID]) -> List[Image]:
    """Fetch every Image whose id is in image_ids.
 
    Silently omits any ids that don't exist — the caller
    (run_batch_inference_service) is responsible for detecting and reporting
    missing ids, so it can give a precise error back to the client.
    """
    if not image_ids:
        return []
    statement = select(Image).where(Image.id.in_(image_ids))
    return session.exec(statement).all()


def create_image(session, image: Image):
    session.add(image)
    session.commit()
    session.refresh(image)
    return image