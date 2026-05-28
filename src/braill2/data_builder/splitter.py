from __future__ import annotations

import os
import random
import shutil
from collections import defaultdict
from pathlib import Path

from .formats.yolo_io import validate_dataset_dir

DEFAULT_TRAIN_RATIO = 0.65
DEFAULT_VAL_RATIO   = 0.2
DEFAULT_TEST_RATIO  = 0.15
DEFAULT_SEED        = 42

SPLIT_NAMES = ("train", "val", "test")

def _group_by_source(
    pairs: list[tuple[str, str]],
    source_prefixes: dict[str, str],
) -> dict[str, list[tuple[str, str]]]:
    groups: dict[str, list[tuple[str, str]]] = defaultdict(list)

    for img_path, lbl_path in pairs:
        fname = Path(img_path).name
        matched = False
        for pfx, source in source_prefixes.items():
            if fname.startswith(f"{pfx}_"):
                groups[source].append((img_path, lbl_path))
                matched = True
                break
        if not matched:
            groups["__unknown__"].append((img_path, lbl_path))

    return dict(groups)


def _split_list(
    items: list,
    train_ratio: float,
    val_ratio: float,
    seed: int,
) -> tuple[list, list, list]:
    rng = random.Random(seed)
    shuffled = list(items)
    rng.shuffle(shuffled)

    n = len(shuffled)
    n_train = int(n * train_ratio)
    n_val   = int(n * val_ratio)

    train = shuffled[:n_train]
    val   = shuffled[n_train : n_train + n_val]
    test  = shuffled[n_train + n_val :]
    return train, val, test


def _transfer(
    pairs: list[tuple[str, str]],
    split_name: str,
    images_root: str,
    labels_root: str,
    copy: bool,
) -> None:
    dst_images = os.path.join(images_root, split_name)
    dst_labels = os.path.join(labels_root, split_name)
    os.makedirs(dst_images, exist_ok=True)
    os.makedirs(dst_labels, exist_ok=True)

    transfer_fn = shutil.copy2 if copy else shutil.move

    for img_path, lbl_path in pairs:
        transfer_fn(img_path, os.path.join(dst_images, Path(img_path).name))
        transfer_fn(lbl_path, os.path.join(dst_labels, Path(lbl_path).name))


def split_dataset(
    dataset_dir: str,
    source_prefixes: dict[str, str],
    train_ratio: float = DEFAULT_TRAIN_RATIO,
    val_ratio: float   = DEFAULT_VAL_RATIO,
    test_ratio: float  = DEFAULT_TEST_RATIO,
    seed: int          = DEFAULT_SEED,
    copy: bool         = False,
    stratify: bool     = True,
) -> dict[str, list[tuple[str, str]]]:
    if abs(train_ratio + val_ratio + test_ratio - 1.0) > 1e-6:
        raise ValueError("train_ratio + val_ratio + test_ratio must equal 1.0")

    images_dir = os.path.join(dataset_dir, "images")
    labels_dir = os.path.join(dataset_dir, "labels")

    if not validate_dataset_dir(images_dir, labels_dir):
        raise ValueError(f"Dataset validation failed for {dataset_dir!r}")

    all_pairs: list[tuple[str, str]] = []
    for fname in sorted(os.listdir(images_dir)):
        full_img = os.path.join(images_dir, fname)
        if os.path.isdir(full_img):
            continue  # skip train/val/test sub-dirs from a previous run
        stem = Path(fname).stem
        full_lbl = os.path.join(labels_dir, f"{stem}.txt")
        if os.path.exists(full_lbl):
            all_pairs.append((full_img, full_lbl))

    result: dict[str, list[tuple[str, str]]] = {s: [] for s in SPLIT_NAMES}

    if stratify:
        groups = _group_by_source(all_pairs, source_prefixes)
        for source_name, pairs in groups.items():
            tr, va, te = _split_list(pairs, train_ratio, val_ratio, seed)
            result["train"].extend(tr)
            result["val"].extend(va)
            result["test"].extend(te)
    else:
        tr, va, te = _split_list(all_pairs, train_ratio, val_ratio, seed)
        result["train"].extend(tr)
        result["val"].extend(va)
        result["test"].extend(te)

    for split_name in SPLIT_NAMES:
        _transfer(result[split_name], split_name, images_dir, labels_dir, copy)

    for split_name in SPLIT_NAMES:
        print(f"[splitter] {split_name:5s}: {len(result[split_name])} samples")

    return result