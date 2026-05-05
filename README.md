# Braill. 2

A Braille Detection and Translation System based on Object Detection.

### Environment Setup

#### Create Environment

We use python version 3.12.

Conda:

```
conda create -n braill2 python=3.12
```

or,

Venv:

```
python -3.12 -m venv venv
```

#### Activate Environment

If using Conda:

```
conda activate braill2
```

or,

If using Venv:

On Windows:

```
venv/Source/activate
```

On MacOS / Linux:

```
source venv/bin/activate
```

#### Install Requirements

```
pip install requirements.txt
```

### Raw Dataset

- Download Angelina Dataset from https://github.com/IlyaOvodov/AngelinaDataset
- and, DSBI Dataset from https://github.com/yeluo1994/DSBI
- Place the extracted folders inside `data/raw` directory.

### Build Dataset

In the root directory, run the build command as a module:

```
python -m src.data_builder.main
```

### Train Model

To train on cells:

```
python train.py --target cells --model yolo26n.pt --epochs 100 --batch 8 --imgsz 640 --device 0
```

To train on characters:

```
python train.py --target characters --model yolo26n.pt --epochs 100 --batch 8 --imgsz 640 --device 0
```

To fine-tune model trained on cells with the characters dataset:

```
python train.py --target characters --model runs/cells_run/weights/best.pt --epochs 100 --batch 8 --imgsz 640 --device 0
```

## Citations

```
@software{yolo26_ultralytics,
  author = {Glenn Jocher and Jing Qiu},
  title = {Ultralytics YOLO26},
  version = {26.0.0},
  year = {2026},
  url = {https://github.com/ultralytics/ultralytics},
  orcid = {0000-0001-5950-6979, 0000-0003-3783-7069},
  license = {AGPL-3.0}
}
```
