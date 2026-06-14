from typing import Annotated
from fastapi import APIRouter, Depends, status
from sqlmodel import Session

from backend.app.core.database import get_session
from backend.app.schemas.auth import LoginRequest, SignupRequest, TokenResponse
from backend.app.schemas.user import UserResponse
from backend.app.services.auth import login as auth_login, signup as auth_signup

auth_router = APIRouter(prefix="/api/auth", tags=["Auth"])

SessionDep = Annotated[Session, Depends(get_session)] 


@auth_router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, session: SessionDep):
    return auth_login(session, payload.identifier, payload.password)

@auth_router.post("/signup", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def signup(payload: SignupRequest, session: SessionDep):
    return auth_signup(session, payload.email, payload.password)
