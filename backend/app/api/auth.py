from typing import Annotated
from fastapi import APIRouter, Depends, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlmodel import Session

from backend.app.api.dependencies import get_current_user
from backend.app.core.database import get_session
from backend.app.models.user import User
from backend.app.schemas.auth import LoginRequest, SignupRequest, TokenResponse
from backend.app.schemas.user import UserResponse
from backend.app.services.auth import login as auth_login, signup as auth_signup

auth_router = APIRouter(prefix="/auth", tags=["Auth"])

@auth_router.post("/login-oauth")
async def login_oauth(
    form_data: OAuth2PasswordRequestForm = Depends(),
    session: Annotated[Session, Depends(get_session)] = None
):
    return auth_login(session, form_data.username, form_data.password)

@auth_router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, session: Annotated[Session, Depends(get_session)]):
    return auth_login(session, payload.identifier, payload.password)

@auth_router.post("/signup", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def signup(payload: SignupRequest, session: Annotated[Session, Depends(get_session)]):
    return auth_signup(session, payload.email, payload.password)

@auth_router.post("/me", response_model=UserResponse)
async def get_me(current_user: Annotated[User, Depends(get_current_user)]):
    return current_user