from ultralytics import YOLO
from pathlib import Path

model=YOLO("yolo26s.pt")

model.train(
    data="configs/data.yaml",
    epochs=20,
    imgsz=640,
    batch=4,
    device=0,
    lr0=0.01,
    lrf=0.001,
    momentum=0.937,
    cos_lr=True,
    warmup_epochs=5.0,
    warmup_bias_lr=0.1,      
    workers=4,
    # cache="disk",
    amp=True,
    # box=9.0,
    # cls=1.5,
    # dfl=1.0,
    hsv_v=0.3,
    hsv_s=0.2,
    hsv_h=0.0,
    translate=0.05,
    scale=0.3,
    mosaic=0.0,
    fliplr=0.0,
    mixup=0.0,
    copy_paste=0.0,
    degrees=0.0,
    seed=0,
    deterministic=True,           
    optimizer="MuSGD",
    project=str(Path.cwd() / "runs")
)