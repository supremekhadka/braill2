from typing import Annotated

from fastapi import APIRouter, Depends, UploadFile, status
from sqlmodel import Session

from uuid import UUID
from backend.app.api.dependencies import get_current_user
from backend.app.core.database import get_session
from backend.app.models.user import User
from backend.app.schemas.image import ImageResponse
from backend.app.services.image import store_image
from backend.app.repositories.image_repository import get_image_by_id
from fastapi.responses import FileResponse
from fastapi import HTTPException, status

image_router = APIRouter(prefix="/api/image", tags=["Image"])


@image_router.get("/{image_id}")
async def get_image_file(
    image_id: UUID,
    current_user: Annotated[User, Depends(get_current_user)],
    session: Annotated[Session, Depends(get_session)],
):
    image = get_image_by_id(session, image_id)
    if image is None:
        raise HTTPException(status_code=404, detail="Image not found")
    if image.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to access this image")
    return FileResponse(image.image_path)

@image_router.post("/upload", response_model=ImageResponse, status_code=status.HTTP_201_CREATED)
async def upload_image(
    file: UploadFile, 
    current_user: Annotated[User, Depends(get_current_user)], 
    session: Annotated[Session, Depends(get_session)]
):
    content = await file.read()

    return store_image(
        session=session,
        file_bytes=content,
        filename=file.filename,
        user_id=current_user.id,
    )