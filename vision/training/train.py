import argparse
from datetime import datetime
from zoneinfo import ZoneInfo
from pathlib import Path

from dotenv import parser
from ultralytics import YOLO

local_time = datetime.now(ZoneInfo("Asia/Kathmandu"))

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Train a YOLO model."
    )

    parser.add_argument("--model", type=str, default="yolo26n.pt")
    parser.add_argument("--data", type=str, default="configs/data.yaml")

    parser.add_argument("--epochs", type=int, default=25)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", default=0)
    parser.add_argument("--workers", type=int, default=4)

    parser.add_argument("--optimizer", type=str, default="MuSGD")

    parser.add_argument("--lr0", type=float, default=0.01)
    parser.add_argument("--lrf", type=float, default=0.001)
    parser.add_argument("--momentum", type=float, default=0.937)

    parser.add_argument("--cos-lr", action="store_true", default=True)

    parser.add_argument("--warmup-epochs", type=float, default=5.0)
    parser.add_argument("--warmup-bias-lr", type=float, default=0.1)

    parser.add_argument("--amp", action="store_true", default=True)

    parser.add_argument("--hsv-v", type=float, default=0.3)
    parser.add_argument("--hsv-s", type=float, default=0.2)
    parser.add_argument("--hsv-h", type=float, default=0.0)

    parser.add_argument("--translate", type=float, default=0.05)
    parser.add_argument("--scale", type=float, default=0.3)

    parser.add_argument("--mosaic", type=float, default=0.0)
    parser.add_argument("--fliplr", type=float, default=0.0)
    parser.add_argument("--mixup", type=float, default=0.0)
    parser.add_argument("--copy-paste", type=float, default=0.0)
    parser.add_argument("--degrees", type=float, default=0.0)

    parser.add_argument("--seed", type=int, default=0)

    parser.add_argument(
        "--deterministic",
        action="store_true",
        default=True,
    )

    parser.add_argument(
        "--project",
        type=str,
        default=str(Path.cwd() / "runs" / "yolo26n" / local_time.strftime("%Y-%m-%d_%H-%M-%S")),
    )
    return parser

def main() -> None:
    args = build_parser().parse_args()

    model = YOLO(args.model)

    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        lr0=args.lr0,
        lrf=args.lrf,
        momentum=args.momentum,
        cos_lr=args.cos_lr,
        warmup_epochs=args.warmup_epochs,
        warmup_bias_lr=args.warmup_bias_lr,
        workers=args.workers,
        amp=args.amp,
        hsv_v=args.hsv_v,
        hsv_s=args.hsv_s,
        hsv_h=args.hsv_h,
        translate=args.translate,
        scale=args.scale,
        mosaic=args.mosaic,
        fliplr=args.fliplr,
        mixup=args.mixup,
        copy_paste=args.copy_paste,
        degrees=args.degrees,
        seed=args.seed,
        deterministic=args.deterministic,
        optimizer=args.optimizer,
        project=args.project,
    )

if __name__ == "__main__":
    main()