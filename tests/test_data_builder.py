from pathlib import Path

import pytest

from vision.data_builder.cropper import crop_dataset
from vision.data_builder.splitter import split_dataset


def test_split_dataset_creates_balanced_splits(populated_dataset):
    result = split_dataset(
        str(populated_dataset),
        source_prefixes={"A": "alpha", "B": "beta"},
        train_ratio=0.7,
        val_ratio=0.2,
        test_ratio=0.1,
        seed=42,
        copy=True,
    )

    assert set(result) == {"train", "val", "test"}
    assert len(result["train"]) == 14
    assert len(result["val"]) == 4
    assert len(result["test"]) == 2

    split_images = []

    for split in ("train", "val", "test"):
        split_dir = populated_dataset / "images" / split

        assert split_dir.exists()

        split_images.extend(
            image.name
            for image in split_dir.glob("*.jpg")
        )

    assert len(split_images) == 20
    assert len(split_images) == len(set(split_images))


def test_split_dataset_invalid_ratios(populated_dataset):
    with pytest.raises(ValueError, match="must equal 1.0"):
        split_dataset(
            str(populated_dataset),
            source_prefixes={"A": "alpha"},
            train_ratio=0.6,
            val_ratio=0.2,
            test_ratio=0.1,
        )


def test_crop_dataset_creates_images_and_labels(
    single_train_dataset,
    tmp_path,
):
    output_dir = tmp_path / "output"

    totals = crop_dataset(
        str(single_train_dataset),
        str(output_dir),
        crop_size=64,
        overlap_ratio=0.1,
    )

    assert totals == {
        "train": 1,
        "val": 0,
        "test": 0,
    }

    image_dir = output_dir / "images" / "train"
    label_dir = output_dir / "labels" / "train"

    assert len(list(image_dir.glob("*.jpg"))) == 1
    assert len(list(label_dir.glob("*.txt"))) == 1