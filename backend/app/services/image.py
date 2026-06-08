from sqlalchemy.orm import Session

from backend.app.repositories.image_repository import create_image, get_image_by_id


def store_image(session: Session, image_path: str, user_id: str):
    return create_image(session, user_id, image_path)

def get_image(session: Session, image_id: int):
    return get_image_by_id(session, image_id)