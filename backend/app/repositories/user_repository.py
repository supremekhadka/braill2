from sqlmodel import Session, select, or_

from backend.app.models.user import User
from backend.app.core.config import settings

database_url = settings.database_url

def create_user(session: Session, email: str, username: str, password_hash: str) -> User:
    user = User(
        email=email,
        username=username,
        password_hash=password_hash
    )

    session.add(user)
    session.commit()
    session.refresh(user)

    return user

def get_user_by_id(session: Session, user_id: int) -> User:
    statement = select(User).where(User.id == user_id)
    return session.exec(statement).first()

def get_user_by_email(session: Session, email: str) -> User:
    statement = select(User).where(User.email == email)
    return session.exec(statement).first()

def get_user_by_identifier(session: Session, identifier: str):
    statement = select(User).where(
        or_(
            User.email == identifier,
            User.username == identifier
        )
    )
    return session.exec(statement).first()