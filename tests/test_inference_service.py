import pytest

from backend.app.services.inference import run_inference_service


class DummySession:
    pass


class DummyImage:
    def __init__(self, image_path: str):
        self.image_path = image_path


def test_successful_inference_returns_extracted_text_and_annotations(patch_inference_dependencies):
    patch_inference_dependencies(image_exists=True, extracted_text="hello", annotations=[{"class_id": 0, "text": "h"}])

    result = run_inference_service(DummySession(), image_id="img-1", lang="en")

    assert result["extracted_text"] == "hello"
    assert result["annotations"] == [{"class_id": 0, "text": "h"}]


def test_invalid_image_id_raises_value_error(patch_inference_dependencies):
    patch_inference_dependencies(image_exists=False)

    with pytest.raises(ValueError, match="Image not found"):
        run_inference_service(DummySession(), image_id="missing", lang="en")


def test_unsupported_language_is_rejected(monkeypatch):
    monkeypatch.setattr(
        "backend.app.services.inference.get_image_by_id",
        lambda session, image_id: DummyImage("/tmp/image.jpg"),
    )
    monkeypatch.setattr(
        "backend.app.services.inference.InferenceConfig.resolve_cfg",
        lambda lang: (_ for _ in ()).throw(ValueError("Unsupported language")),
    )

    with pytest.raises(ValueError, match="Unsupported language"):
        run_inference_service(DummySession(), image_id="img-1", lang="fr")
