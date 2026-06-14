# Braill. 2

A Braille Detection and Translation System based on Object Detection.

## Environment Setup

### Create Environment

Conda:

```bash
conda create -n braill2 python=3.12
```

Venv:

```
python -m venv venv
```

### Activate Environment

Conda:

```
conda activate braill2
```

Venv:

Windows:

```
venv/Scripts/activate
```

MacOS / Linux:

```
source venv/bin/activate
```

### Install Requirements

```
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements.txt
```

### Raw Dataset

- Download Angelina Dataset from https://github.com/IlyaOvodov/AngelinaDataset
- and, DSBI Dataset from https://github.com/yeluo1994/DSBI
- Place the extracted folders inside `data/raw` directory.

### Build Dataset

In the root directory, run the build command as a module:

```
python -m vision.data_builder.main --num-synthetic 400
```

### Train Model

```
python -m vision.training.train
```

### Predict

```
python -m vision.inference.predict --image /path/to/image --visualize
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
