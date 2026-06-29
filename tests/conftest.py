import uuid
from pathlib import Path
from types import SimpleNamespace

from httpx import ASGITransport, AsyncClient
import cv2
import numpy as np
import pytest

from backend.app.api.dependencies import get_current_user, get_session
from backend.app.main import app


class DummyUser:
    def __init__(
        self,
        user_id=1,
        username="john",
        email="john@example.com",
        password_hash="hashed-password",
    ):
        self.id = user_id
        self.username = username
        self.email = email
        self.password_hash = password_hash


class DummyImage:
    def __init__(
        self,
        image_id=None,
        user_id=1,
        image_path="uploads/sample.jpg",
    ):
        self.id = image_id or uuid.uuid4()
        self.user_id = user_id
        self.image_path = image_path


class DummySession:
    pass


def override_user():
    return DummyUser()


def override_session():
    return DummySession()


app.dependency_overrides[get_current_user] = override_user
app.dependency_overrides[get_session] = override_session


@pytest.fixture
def test_user():
    return DummyUser()


@pytest.fixture
def test_image():
    return DummyImage()


@pytest.fixture
def valid_email(test_user):
    return test_user.email


@pytest.fixture
def invalid_email():
    return "unknown@example.com"


@pytest.fixture
def valid_password():
    return "password123"


@pytest.fixture
def invalid_password():
    return "wrong-password"


@pytest.fixture
def valid_credentials(valid_email, valid_password):
    return {
        "identifier": valid_email,
        "password": valid_password,
    }


@pytest.fixture
def invalid_credentials(valid_email, invalid_password):
    return {
        "identifier": valid_email,
        "password": invalid_password,
    }


@pytest.fixture
def image_bytes():
    return b"fake-image-bytes"


@pytest.fixture
def filename():
    return "sample.jpg"


@pytest.fixture
async def api_client():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
        yield client


@pytest.fixture
def sample_image():
    image = np.zeros((64, 64, 3), dtype=np.uint8)
    image[:, :, 0] = 255
    return image


@pytest.fixture
def label_text():
    return "0 0.5 0.5 0.5 0.5\n"


@pytest.fixture
def populated_dataset(tmp_path, sample_image, label_text):
    dataset_dir = tmp_path / "dataset"
    images_dir = dataset_dir / "images"
    labels_dir = dataset_dir / "labels"

    images_dir.mkdir(parents=True)
    labels_dir.mkdir(parents=True)

    filenames = (
        [f"A_{i:02d}.jpg" for i in range(1, 11)]
        + [f"B_{i:02d}.jpg" for i in range(1, 11)]
    )

    for filename in filenames:
        image_path = images_dir / filename
        label_path = labels_dir / f"{Path(filename).stem}.txt"

        cv2.imwrite(str(image_path), sample_image)
        label_path.write_text(label_text)

    return dataset_dir


@pytest.fixture
def single_train_dataset(tmp_path, sample_image, label_text):
    dataset_dir = tmp_path / "dataset"

    image_dir = dataset_dir / "images" / "train"
    label_dir = dataset_dir / "labels" / "train"

    image_dir.mkdir(parents=True)
    label_dir.mkdir(parents=True)

    cv2.imwrite(str(image_dir / "sample.jpg"), sample_image)
    (label_dir / "sample.txt").write_text(label_text)

    return dataset_dir


@pytest.fixture
def patch_inference_dependencies(monkeypatch):
    def _patch(image_exists: bool, extracted_text: str = "hello", annotations=None):
        annotations = annotations or [{"class_id": 0, "text": "h"}]

        monkeypatch.setattr(
            "backend.app.services.inference.get_image_by_id",
            lambda session, image_id: DummyImage("/tmp/image.jpg") if image_exists else None,
        )
        monkeypatch.setattr(
            "backend.app.services.inference.InferenceConfig.resolve_cfg",
            lambda lang: {"lang": lang},
        )
        monkeypatch.setattr(
            "backend.app.services.inference.pipeline",
            lambda image_path, cfg: {
                "extracted_text": extracted_text,
                "annotations": annotations,
            },
        )
        monkeypatch.setattr(
            "backend.app.services.inference.create_inference_result",
            lambda session, image_id, extracted_text, annotations, lang: SimpleNamespace(
                extracted_text=extracted_text,
                annotations=annotations,
            ),
        )

    return _patch
