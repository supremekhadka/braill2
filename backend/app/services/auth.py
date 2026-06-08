from datetime import datetime, timedelta, timezone

import jwt

from fastapi import HTTPException, status
from sqlmodel import Session

from backend.app.core.config import settings
from backend.app.models.user import User
from backend.app.repositories.user_repository import create_user, get_user_by_email, get_user_by_identifier
from backend.app.schemas.auth import TokenResponse
from backend.app.core.security import hash_password, verify_password

def authenticate_user(session: Session, identifier: str, password: str):
    user = get_user_by_identifier(session, identifier)

    if not user:
        return None

    if not verify_password(password, user.password_hash):
        return None

    return user

def create_access_token(data: dict, expires_delta: timedelta) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta

    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt

def login(
    session: Session,
    identifier: str,
    password: str       
) -> TokenResponse:
    user = authenticate_user(session, identifier, password)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE)

    access_token = create_access_token(
        data={"sub": str(user.id)}, expires_delta=access_token_expires
    )
    return TokenResponse(access_token=access_token, token_type="bearer")

def signup(
        session: Session, 
        email: str,
        password: str
) -> User:
    existing_user = get_user_by_email(session, email)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )
    
    username = email.split("@")[0]
    password_hash = hash_password(password)
    return create_user(session, email, username, password_hash)

def logout():
    pass