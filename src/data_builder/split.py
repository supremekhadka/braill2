import os
import random
import shutil
from pathlib import Path

SEED = 42

TRAIN_RATIO=0.6
VAL_RATIO=0.2
TEST_RATIO=0.2

DATASET_PATH = "./dataset"

random.seed(SEED)

def validate_raw_dataset(images_dir, labels_dir):
    images = set(os.listdir(images_dir))
    labels = set(os.listdir(labels_dir))

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

def split_dataset(dataset_dir, angelina_prefix, dsbi_prefix, train_ratio=0.6, val_ratio=0.2, test_ratio=0.2, seed=42):
    assert abs(train_ratio + val_ratio + test_ratio - 1.0) < 1e-6
    random.seed(seed)

    images_dir = os.path.join(dataset_dir, "images")
    labels_dir = os.path.join(dataset_dir, "labels")

    if not validate_raw_dataset(images_dir, labels_dir):
        raise ValueError(f"Dataset validation failed for {dataset_dir}")

    ang, dsbi = [], []

    for img in os.listdir(images_dir):
        # Skip directories if script is re-run
        if os.path.isdir(os.path.join(images_dir, img)):
            continue
            
        img_path = os.path.join(images_dir, img)
        lbl_path = os.path.join(labels_dir, Path(img).stem + ".txt")

        if img.startswith(f"{angelina_prefix}_"):
            ang.append((img_path, lbl_path))
        elif img.startswith(f"{dsbi_prefix}_"):
            dsbi.append((img_path, lbl_path))

    def split_group(group):
        random.shuffle(group)
        n = len(group)
        train_end = int(n * train_ratio)
        val_end = train_end + int(n * val_ratio)
        
        train = group[:train_end]
        val = group[train_end:val_end]
        test = group[val_end:]
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