from typing import Annotated

from fastapi import APIRouter, Depends, UploadFile, status
from sqlmodel import Session

from backend.app.api.dependencies import get_current_user
from backend.app.core.database import get_session
from backend.app.models.user import User
from backend.app.schemas.image import ImageResponse
from backend.app.services.image import store_image

image_router = APIRouter(prefix="/image", tags=["Image"])

@image_router.post("/upload", response_model=ImageResponse, status_code=status.HTTP_201_CREATED)
async def upload_image(
    file: UploadFile, 
    current_user: Annotated[User, Depends(get_current_user)], 
    session: Annotated[Session, Depends(get_session)]
):
    image = store_image(session, file.filename, current_user.id)
    return image