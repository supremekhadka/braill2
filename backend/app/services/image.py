from uuid import uuid4
from pathlib import Path
from sqlalchemy.orm import Session
from uuid import UUID

from backend.app.repositories.image_repository import create_image, get_image_by_id
from backend.app.core.configs import settings
from backend.app.models.image import Image


# UPLOAD_DIR = Path(settings.UPLOAD_DIR)
UPLOAD_DIR = Path("./uploads")
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

def store_image(session, file_bytes: bytes, filename: str, user_id):
    file_ext = Path(filename).suffix.lower()
    image_id = uuid4()

    stored_filename = f"{image_id}{file_ext}"
    file_path = UPLOAD_DIR / stored_filename

    with file_path.open("wb") as f:
        f.write(file_bytes)

    image = Image(
        user_id=user_id,
        image_path=str(file_path),
    )

    return create_image(session, image)

def get_image(session: Session, image_id: UUID):
    return get_image_by_id(session, image_id)