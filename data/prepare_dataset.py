import os
import pandas as pd
import shutil

from pathlib import Path

ANGELINA_PREFIX="ANG"
DSBI_PREFIX="DSBI"

RAW_DATASETS_PATH="../raw-datasets"
TARGET_IMAGE_DATASET_PATH="./dataset/images"
TARGET_LABEL_DATASET_PATH="./dataset/labels"

IGNORE_DIRS = ['.gitignore', 'pics', 'src', 'README.md', 'train.txt', 'val.txt', 'test.txt', 'figures']

def make_dir_if_not_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)

def get_prefix(dataset_name):
    if dataset_name == "AngelinaDataset-master":
        return ANGELINA_PREFIX
    elif dataset_name == "DSBI-master":
        return DSBI_PREFIX
    else:
        raise ValueError(f"Unknown dataset name: {dataset_name}")

def build_dataset(raw_dataset_path, target_image_path, target_label_path):
    dataset_name = os.path.basename(raw_dataset_path)
    prefix = get_prefix(dataset_name)
    
    make_dir_if_not_exists(target_image_path)
    make_dir_if_not_exists(target_label_path)

    for i in os.listdir(raw_dataset_path):
        if i in IGNORE_DIRS:
            continue
        for j in os.listdir(os.path.join(raw_dataset_path, i)):
            if j in IGNORE_DIRS:
                continue    
            for k in os.listdir(os.path.join(raw_dataset_path, i, j)):
                if dataset_name == "AngelinaDataset-master":
                    if k in IGNORE_DIRS:
                        continue
                    if Path(k).suffix in ['.jpg', '.jpeg', '.png']: 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_image_path, f"{prefix}_{k}"))
                    if Path(k).suffix in ['.csv']: 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_label_path, f"{prefix}_{k}"))
                if dataset_name == "DSBI-master":
                    if Path(k).suffix in ['.jpg', '.jpeg', '.png'] and os.path.basename(k).rsplit("+",1)[1].split(".")[0] == "recto": 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_image_path, f"{prefix}_{k}"))
                    if Path(k).suffix in ['.txt'] and os.path.basename(k).rsplit("+",1)[1].split(".")[0] == "recto": 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_label_path, f"{prefix}_{k}"))
                
def parse_angelina(label_path):
    rows=[]
    with open(label_path, 'r') as file:
        for line in file:
            line=line.strip()
            if line:
                x1, y1, x2, y2, c = line.split(';')
                width = (float(x2)) - float(x1)    
                height = float(y2) - float(y1)
                x_c = float(x1) + width / 2
                y_c = float(y1) + height / 2

                rows.append([x_c, y_c, width, height, c])
    
    with open("annotation_name.txt", 'w') as file:        
        for row in rows:
            file.write(' '.join(map(str, row)) + '\n')



if __name__ == '__main__':
    for i in os.listdir(RAW_DATASETS_PATH):
        if i in IGNORE_DIRS:
            continue
        build_dataset(os.path.join(RAW_DATASETS_PATH, i), TARGET_IMAGE_DATASET_PATH, TARGET_LABEL_DATASET_PATH)