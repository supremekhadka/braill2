# Braill. 2

## Build Dataset

In the root directory,

```
python -m src.build_dataset.main
```

## Train Model

To train on cells:

```
python train.py --target cells --model yolo26n.pt --epochs 100 --batch 8 --imgsz 640 --device 0
```

To train on characters:

```
python train.py --target characters --model yolo26n.pt --epochs 100 --batch 8 --imgsz 640 --device 0
```

To fine-tune on cells-trained model on characters dataset:

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
