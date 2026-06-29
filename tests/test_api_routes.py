from datetime import datetime, timezone
from uuid import uuid4

import pytest


@pytest.mark.anyio
async def test_login(monkeypatch, api_client):
    monkeypatch.setattr(
        "backend.app.api.auth.auth_login",
        lambda session, identifier, password: {
            "access_token": "token",
            "token_type": "bearer",
        },
    )

    response = await api_client.post(
        "/api/auth/login",
        json={"identifier": "user@test.com", "password": "password"},
    )

    assert response.status_code == 200
    assert response.json()["token_type"] == "bearer"


@pytest.mark.anyio
async def test_image_upload(monkeypatch, api_client):
    image_id = str(uuid4())
    monkeypatch.setattr(
        "backend.app.api.image.store_image",
        lambda session, file_bytes, filename, user_id: {
            "id": image_id,
            "image_path": "/tmp/sample.jpg",
            "uploaded_at": datetime.now(timezone.utc).isoformat(),
        },
    )

    response = await api_client.post(
        "/api/image/upload",
        files={"file": ("sample.jpg", b"image-bytes", "image/jpeg")},
    )

    assert response.status_code == 201
    assert response.json()["id"] == image_id


@pytest.mark.anyio
async def test_prediction(monkeypatch, api_client):
    image_id = str(uuid4())
    monkeypatch.setattr(
        "backend.app.api.inference.run_inference_service",
        lambda session, image_id, lang: {
            "extracted_text": "hello",
            "annotations": [
                {"class_id": 0, "x1": 0.0, "y1": 0.0, "x2": 1.0, "y2": 1.0}
            ],
        },
    )

    response = await api_client.post(
        "/api/inference/predict",
        json={"image_id": image_id, "lang": "en"},
    )

    assert response.status_code == 200
    assert response.json()["extracted_text"] == "hello"


@pytest.mark.anyio
async def test_history(monkeypatch, api_client):
    monkeypatch.setattr(
        "backend.app.api.inference.get_prediction_history",
        lambda session, user_id: [{"extracted_text": "hello", "annotations": []}],
    )

    response = await api_client.get("/api/inference/history")

    assert response.status_code == 200
    assert len(response.json()) == 1


@pytest.mark.anyio
async def test_unknown_route(api_client):
    response = await api_client.get("/api/does-not-exist")

    assert response.status_code == 404