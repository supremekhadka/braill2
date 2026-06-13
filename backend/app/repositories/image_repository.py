from sqlmodel import Session, select
from uuid import UUID

from backend.app.models.image import Image

def get_image_by_id(session: Session, image_id: UUID):
    statement = select(Image).where(Image.id == image_id)
    return session.exec(statement).first()

def create_image(session, image: Image):
    session.add(image)
    session.commit()
    session.refresh(image)
    return image