from sqlmodel import Session, select

from backend.app.models.image import Image

def get_image_by_id(session: Session, image_id: int):
    statement = select(Image).where(Image.id == image_id)
    return session.exec(statement).first()

def create_image(session: Session, user_id: str, image_path: str):
    image = Image(
        user_id=user_id,
        image_path=image_path
    )

    session.add(image)
    session.commit()
    session.refresh(image)

    return image