import jwt
import pytest

from datetime import timedelta
from fastapi import HTTPException

from backend.app.core.configs import settings
from backend.app.services.auth import (
    authenticate_user,
    create_access_token,
    login,
    signup,
)


def test_authenticate_user_success(
    mocker,
    test_user,
    valid_email,
    valid_password
):
    mocker.patch(
        "backend.app.services.auth.get_user_by_identifier",
        return_value=test_user,
    )

    mocker.patch(
        "backend.app.services.auth.verify_password",
        return_value=True,
    )

    result = authenticate_user(
        session=None,
        identifier=valid_email,
        password=valid_password        
    )

    assert result == test_user


def test_authenticate_user_unknown_user(
    mocker,
    invalid_email,
    valid_password,
):
    mocker.patch(
        "backend.app.services.auth.get_user_by_identifier",
        return_value=None,
    )

    result = authenticate_user(
        session=None,
        identifier=invalid_email,
        password=valid_password
    )

    assert result is None


def test_authenticate_user_invalid_password(
    mocker,
    test_user,
    valid_email,
    invalid_password
):
    mocker.patch(
        "backend.app.services.auth.get_user_by_identifier",
        return_value=test_user,
    )

    mocker.patch(
        "backend.app.services.auth.verify_password",
        return_value=False,
    )

    result = authenticate_user(
        session=None,
        identifier=valid_email,
        password=invalid_password,
    )

    assert result is None


def test_create_access_token_contains_subject():
    token = create_access_token(
        {"sub": "1"},
        timedelta(minutes=30),
    )

    payload = jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
    )

    assert payload["sub"] == "1"
    assert "exp" in payload


def test_login_success(
    mocker,
    test_user,
    valid_credentials,
):
    mocker.patch(
        "backend.app.services.auth.authenticate_user",
        return_value=test_user,
    )

    token = login(
        session=None,
        **valid_credentials,
    )

    assert token.token_type == "bearer"
    assert isinstance(token.access_token, str)
    assert len(token.access_token) > 20


def test_login_invalid_credentials(
    mocker,
    invalid_credentials,
):
    mocker.patch(
        "backend.app.services.auth.authenticate_user",
        return_value=None,
    )

    with pytest.raises(HTTPException) as exc:
        login(
            session=None,
            **invalid_credentials,
        )

    assert exc.value.status_code == 401


def test_signup_success(
    mocker,
    test_user,
    valid_email,
    valid_password,
):
    mocker.patch(
        "backend.app.services.auth.get_user_by_email",
        return_value=None,
    )

    hash_mock = mocker.patch(
        "backend.app.services.auth.hash_password",
        return_value="hashed-password",
    )

    create_mock = mocker.patch(
        "backend.app.services.auth.create_user",
        return_value=test_user,
    )

    result = signup(
        session=None,
        email=valid_email,
        password=valid_password,
    )

    hash_mock.assert_called_once_with(valid_password)
    create_mock.assert_called_once()

    assert result == test_user


def test_signup_existing_email(
    mocker,
    test_user,
    valid_email,
    valid_password,
):
    mocker.patch(
        "backend.app.services.auth.get_user_by_email",
        return_value=test_user,
    )

    with pytest.raises(HTTPException) as exc:
        signup(
            session=None,
            email=valid_email,
            password=valid_password,
        )

    assert exc.value.status_code == 400
    assert exc.value.detail == "Email already registered"