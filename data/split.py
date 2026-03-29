import os
import random
import shutil
from pathlib import Path

SEED = 42

TRAIN_RATIO=0.6
VAL_RATIO=0.2
TEST_RATIO=0.2

DATASET_PATH = "../data/dataset"

random.seed(SEED)

def validate_dataset(dataset_path):
    images = set(os.listdir(os.path.join(dataset_path, "images")))
    labels = set(os.listdir(os.path.join(dataset_path, "labels")))

    image_basenames = set([os.path.splitext(img)[0] for img in images])
    label_basenames = set([os.path.splitext(lbl)[0] for lbl in labels])

    if image_basenames != label_basenames:
        missing_images = label_basenames - image_basenames
        missing_labels = image_basenames - label_basenames

        if missing_images:
            print(f"Missing images for labels: {missing_images}")
        if missing_labels:
            print(f"Missing labels for images: {missing_labels}")
        return False
    
    return True

def split(dataset_path, train_ratio, val_ratio, test_ratio):
    assert abs(train_ratio + val_ratio + test_ratio - 1.0) < 1e-6

    images_dir = os.path.join(dataset_path, "images")
    labels_dir = os.path.join(dataset_path, "labels")

    ang, dsbi = [], []

    for img in os.listdir(images_dir):
        img_path = os.path.join(images_dir, img)
        lbl_path = os.path.join(labels_dir, Path(img).stem + ".txt")

        if img.startswith("ANG_"):
            ang.append((img_path, lbl_path))
        elif img.startswith("DSBI_"):
            dsbi.append((img_path, lbl_path))

    def split_group(group):
        train, val, test = [], [], []
        for item in group:
            r = random.random()
            if r < train_ratio:
                train.append(item)
            elif r < train_ratio + val_ratio:
                val.append(item)
            else:
                test.append(item)
        return train, val, test

    train_a, val_a, test_a = split_group(ang)
    train_d, val_d, test_d = split_group(dsbi)

    train = train_a + train_d
    val = val_a + val_d
    test = test_a + test_d

    for split_name in ["train", "val", "test"]:
        os.makedirs(os.path.join(images_dir, split_name), exist_ok=True)
        os.makedirs(os.path.join(labels_dir, split_name), exist_ok=True)

    def move_files(data, split_name):
        for img_path, lbl_path in data:
            shutil.move(img_path, os.path.join(images_dir, split_name, Path(img_path).name))
            shutil.move(lbl_path, os.path.join(labels_dir, split_name, Path(lbl_path).name))

    move_files(train, "train")
    move_files(val, "val")
    move_files(test, "test")

if __name__ == "__main__":
    if not validate_dataset(DATASET_PATH):
        print("Dataset validation failed. Please fix the issues and try again.")
    else:
        split(DATASET_PATH, TRAIN_RATIO, VAL_RATIO, TEST_RATIO)