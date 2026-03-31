import os
import shutil

from pathlib import Path
from PIL import Image

def make_dir_if_not_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)

def get_prefix(dataset_name, angelina_prefix, dsbi_prefix):
    if dataset_name == "AngelinaDataset-master":
        return angelina_prefix
    elif dataset_name == "DSBI-master":
        return dsbi_prefix
    else:
        raise ValueError(f"Unknown dataset name: {dataset_name}")

def parse_angelina_character(label_path):
    parsed_lines=[]
    with open(label_path, 'r') as file:
        for line in file:
            line=line.strip()
            if line:
                x1, y1, x2, y2, c = line.split(';')
                width = (float(x2)) - float(x1)    
                height = float(y2) - float(y1)
                x_c = float(x1) + width / 2
                y_c = float(y1) + height / 2
                c = int(c) - 1

                parsed_lines.append([c, x_c, y_c, width, height])
    
    return parsed_lines

def parse_angelina_cell(label_path):
    parsed_lines=[]
    with open(label_path, 'r') as file:
        for line in file:
            line=line.strip()
            if line:
                x1, y1, x2, y2, c = line.split(';')
                width = (float(x2)) - float(x1)    
                height = float(y2) - float(y1)
                x_c = float(x1) + width / 2
                y_c = float(y1) + height / 2
                c = 0 # class bbox = 0

                parsed_lines.append([c, x_c, y_c, width, height])
    
    return parsed_lines


def parse_dsbi_character(label_path):
    parsed_lines = []

    with open(label_path, 'r') as file:
        lines = file.readlines()

    if len(lines) <= 3:
        return parsed_lines

    v_lines = [int(x) for x in lines[1].strip().split()]
    h_lines = [int(x) for x in lines[2].strip().split()] 

    for i in range(3, len(lines)):
        parts = lines[i].strip().split()
        if len(parts) < 8:
            continue

        row = int(parts[0])
        col = int(parts[1])

        try:
            x1 = v_lines[2*(col-1)]
            x2 = v_lines[2*(col-1)+1]

            y1 = h_lines[3*(row-1)]
            y2 = h_lines[3*(row-1)+2]
        except IndexError:
            continue

        dots = ''.join(parts[2:][::-1])
        c = int(dots, 2)

        # Skip if the cell is empty (annot == 000000)
        if c == 0:
            continue

        c = c - 1 # convert to 0-based index
        width = x2 - x1
        height = y2 - y1


        x_c = x1 + width / 2
        y_c = y1 + height / 2

        width += 0.8 * width # add 80% of the grid width
        height += 0.5 * height # add 50% of the grid height
        
        parsed_lines.append([c, x_c, y_c, width, height])

    return parsed_lines  

def parse_dsbi_cell(label_path):
    parsed_lines = []

    with open(label_path, 'r') as file:
        lines = file.readlines()

    if len(lines) <= 3:
        return parsed_lines

    v_lines = [int(x) for x in lines[1].strip().split()]
    h_lines = [int(x) for x in lines[2].strip().split()] 

    for i in range(3, len(lines)):
        parts = lines[i].strip().split()
        if len(parts) < 8:
            continue

        row = int(parts[0])
        col = int(parts[1])

        try:
            x1 = v_lines[2*(col-1)]
            x2 = v_lines[2*(col-1)+1]

            y1 = h_lines[3*(row-1)]
            y2 = h_lines[3*(row-1)+2]
        except IndexError:
            continue

        dots = ''.join(parts[2:][::-1])

        # Skip if the cell is empty (annot == 000000)
        if int(dots, 2) == 0:
            continue

        # class bbox = 0
        c = 0

        width = x2 - x1
        height = y2 - y1


        x_c = x1 + width / 2
        y_c = y1 + height / 2

        width += 0.8 * width # add 80% of the grid width
        height += 0.5 * height # add 50% of the grid height
        
        parsed_lines.append([c, x_c, y_c, width, height])

    return parsed_lines  

def normalize_annotations(parsed_lines, img_width, img_height):
    normalized_lines = []
    for line in parsed_lines:
        c, x_c, y_c, width, height = line
        x_c_norm = x_c / img_width
        y_c_norm = y_c / img_height
        width_norm = width / img_width
        height_norm = height / img_height
        normalized_lines.append([c, x_c_norm, y_c_norm, width_norm, height_norm])
    return normalized_lines

def build_dataset(raw_dataset_path, target_dataset_path, angelina_prefix, dsbi_prefix, ignore_dirs):
    dataset_name = os.path.basename(raw_dataset_path)
    prefix = get_prefix(dataset_name, angelina_prefix, dsbi_prefix)

    make_dir_if_not_exists(os.path.join(target_dataset_path, "cells", "images"))
    make_dir_if_not_exists(os.path.join(target_dataset_path, "cells", "labels"))
    make_dir_if_not_exists(os.path.join(target_dataset_path, "cells", "_temp"))

    make_dir_if_not_exists(os.path.join(target_dataset_path, "characters", "images"))
    make_dir_if_not_exists(os.path.join(target_dataset_path, "characters", "labels"))
    make_dir_if_not_exists(os.path.join(target_dataset_path, "characters", "_temp"))

    for i in os.listdir(raw_dataset_path):
        if i in ignore_dirs:
            continue
        for j in os.listdir(os.path.join(raw_dataset_path, i)):
            if j in ignore_dirs:
                continue    
            for k in os.listdir(os.path.join(raw_dataset_path, i, j)):
                if dataset_name == "AngelinaDataset-master":
                    if k in ignore_dirs:
                        continue

                    if Path(k).suffix in ['.jpg', '.jpeg', '.png']: 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "cells", "images", f"{prefix}_{k}"))
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "characters", "images", f"{prefix}_{k}"))

                    if Path(k).suffix in ['.csv']: 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "cells", "_temp", f"{prefix}_{k}"))
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "characters", "_temp", f"{prefix}_{k}"))

                        lines = parse_angelina_cell(os.path.join(target_dataset_path, "cells", "_temp", f"{prefix}_{k}"))
                        with open(os.path.join(target_dataset_path, "cells", "labels", f"{prefix}_{Path(k).stem}.txt"), 'w') as label_file:
                            for line in lines:
                                label_file.write(' '.join(map(str, line)) + '\n')

                        lines = parse_angelina_character(os.path.join(target_dataset_path, "characters", "_temp", f"{prefix}_{k}"))
                        with open(os.path.join(target_dataset_path, "characters", "labels", f"{prefix}_{Path(k).stem}.txt"), 'w') as label_file:
                            for line in lines:
                                label_file.write(' '.join(map(str, line)) + '\n')
                            
                if dataset_name == "DSBI-master":
                    if Path(k).suffix in ['.jpg'] and os.path.basename(k).rsplit("+",1)[1].split(".")[0] == "recto": 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "cells", "images", f"{prefix}_{k}"))
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "characters", "images", f"{prefix}_{k}"))

                    if Path(k).suffix in ['.txt'] and os.path.basename(k).rsplit("+",1)[1].split(".")[0] == "recto": 
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "cells", "_temp", f"{prefix}_{k}"))
                        shutil.copy(os.path.join(raw_dataset_path, i, j, k), os.path.join(target_dataset_path, "characters", "_temp", f"{prefix}_{k}"))

                        lines = parse_dsbi_character(os.path.join(target_dataset_path, "characters", "_temp", f"{prefix}_{k}"))
                        img = Image.open(os.path.join(target_dataset_path, "characters", "images", f"{prefix}_{Path(k).stem}.jpg"))
                        img_width, img_height = img.size
                        lines = normalize_annotations(lines, img_width, img_height)
                        with open(os.path.join(target_dataset_path, "characters", "labels", f"{prefix}_{Path(k).stem}.txt"), 'w') as label_file:
                            for line in lines:
                                label_file.write(' '.join(map(str, line)) + '\n')
                                
                        lines = parse_dsbi_cell(os.path.join(target_dataset_path, "cells", "_temp", f"{prefix}_{k}"))
                        img = Image.open(os.path.join(target_dataset_path, "cells", "images", f"{prefix}_{Path(k).stem}.jpg"))
                        img_width, img_height = img.size
                        lines = normalize_annotations(lines, img_width, img_height)
                        with open(os.path.join(target_dataset_path, "cells", "labels", f"{prefix}_{Path(k).stem}.txt"), 'w') as label_file:
                            for line in lines:
                                label_file.write(' '.join(map(str, line)) + '\n')


    shutil.rmtree(os.path.join(target_dataset_path, "cells", "_temp"))            
    shutil.rmtree(os.path.join(target_dataset_path, "characters", "_temp"))            