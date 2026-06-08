from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlmodel import Session
from jwt.exceptions import InvalidTokenError

from backend.app.core.database import get_session
from backend.app.models.user import User
from backend.app.repositories.user_repository import get_user_by_id
from backend.app.core.config import settings
from backend.app.schemas.auth import TokenData

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login-oauth")

def get_current_user(
        session: Annotated[Session, Depends(get_session)], 
        token: Annotated[str, Depends(oauth2_scheme)]
    ) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"}
    )

    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        sub = payload.get("sub")

        if sub is None:
            raise credentials_exception
        user_id = str(sub)
        token_data = TokenData(user_id=user_id)

    except InvalidTokenError:
        raise credentials_exception
    
    user = get_user_by_id(session, token_data.user_id)
    return user 