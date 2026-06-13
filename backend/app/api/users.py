from typing import Annotated
from fastapi import APIRouter, Depends

from backend.app.api.dependencies import get_current_user
from backend.app.models.user import User
from backend.app.schemas.user import UserResponse

user_router = APIRouter(prefix="/api/users", tags=["Users"])

@user_router.get("/me", response_model=UserResponse)
async def get_me(current_user: Annotated[User, Depends(get_current_user)]):
    return current_user