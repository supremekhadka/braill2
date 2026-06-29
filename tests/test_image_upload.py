from pathlib import Path

from backend.app.services.image import store_image


def test_store_image_success(
    tmp_path,
    mocker,
    test_image,
    image_bytes,
    filename,
):
    mocker.patch(
        "backend.app.services.image.UPLOAD_DIR",
        tmp_path,
    )

    create_image = mocker.patch(
        "backend.app.services.image.create_image",
        return_value=test_image,
    )

    result = store_image(
        session=None,
        file_bytes=image_bytes,
        filename=filename,
        user_id=1,
    )

    assert result == test_image
    create_image.assert_called_once()
    assert len(list(tmp_path.iterdir())) == 1


def test_store_image_unique_filename(
    tmp_path,
    mocker,
    image_bytes,
    filename,
):
    mocker.patch(
        "backend.app.services.image.UPLOAD_DIR",
        tmp_path,
    )

    mocker.patch(
        "backend.app.services.image.create_image",
        side_effect=lambda session, image: image,
    )

    first = store_image(
        None,
        image_bytes,
        filename,
        1,
    )

    second = store_image(
        None,
        image_bytes,
        filename,
        1,
    )

    assert first.image_path != second.image_path


def test_store_image_creates_database_record(
    tmp_path,
    mocker,
    image_bytes,
    filename,
):
    mocker.patch(
        "backend.app.services.image.UPLOAD_DIR",
        tmp_path,
    )

    create_image = mocker.patch(
        "backend.app.services.image.create_image",
        side_effect=lambda session, image: image,
    )

    store_image(
        None,
        image_bytes,
        filename,
        25,
    )

    create_image.assert_called_once()

    image = create_image.call_args.args[1]

    assert image.user_id == 25
    assert Path(image.image_path).exists()