from __future__ import annotations

import argparse
from pathlib import Path

import cv2
import torch
import yaml
from sahi import AutoDetectionModel
from sahi.predict import get_sliced_prediction

with open("configs/model/characters.yaml", "r") as f:
    data = yaml.safe_load(f)

ID_TO_NAME = data["names"]

DEFAULT_DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

DEFAULT_CFG = {
    "slice_size": 640,
    "overlap": 0.1,
    "confidence": 0.4,
    "device": DEFAULT_DEVICE,
}


def get_default_image() -> str:
    p = Path("data/split/images/test")
    if not p.exists():
        return ""

    imgs = sorted([x for x in p.iterdir() if x.suffix.lower() in {".jpg", ".png", ".jpeg"}])
    return str(imgs[0]) if imgs else ""


def build_parser():
    p = argparse.ArgumentParser()

    p.add_argument("--model", type=str, default="runs/train/weights/best.pt")
    p.add_argument("--image", type=str, default=get_default_image())

    p.add_argument("--out-txt", type=str, default="data/output/preds.txt")
    p.add_argument("--out-img", type=str, default="data/output/vis.jpg")

    p.add_argument("--slice-size", type=int, default=640)
    p.add_argument("--overlap", type=float, default=0.1)
    p.add_argument("--confidence", type=float, default=0.4)

    p.add_argument("--visualize", action="store_true")

    return p


def load_model(model_path: str, device: str):
    return AutoDetectionModel.from_pretrained(
        model_type="ultralytics",
        model_path=model_path,
        confidence_threshold=0.4,
        device=device,
    )

def run_sahi(model, image_path: str, slice_size: int, overlap: float):
    return get_sliced_prediction(
        image=image_path,
        detection_model=model,
        slice_height=slice_size,
        slice_width=slice_size,
        overlap_height_ratio=overlap,
        overlap_width_ratio=overlap,
        postprocess_type="NMM",
        verbose=False,
    )


def save_txt(pred, image_path: str, out_path: str):
    img = cv2.imread(image_path)
    h, w = img.shape[:2]

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)

    with open(out_path, "w") as f:
        for obj in pred.object_prediction_list:

            class_id = obj.category.id

            x1 = obj.bbox.minx
            y1 = obj.bbox.miny
            x2 = obj.bbox.maxx
            y2 = obj.bbox.maxy

            cx = ((x1 + x2) / 2) / w
            cy = ((y1 + y2) / 2) / h
            bw = (x2 - x1) / w
            bh = (y2 - y1) / h

            f.write(f"{class_id} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n")


def visualize(image_path: str, pred, out_path: str):
    img = cv2.imread(image_path)

    for obj in pred.object_prediction_list:
        x1, y1, x2, y2 = map(int, [
            obj.bbox.minx,
            obj.bbox.miny,
            obj.bbox.maxx,
            obj.bbox.maxy,
        ])

        class_id = obj.category.id
        label = ID_TO_NAME.get(class_id, str(class_id))

        cv2.rectangle(img, (x1, y1), (x2, y2), (0, 255, 0), 2)

        font_scale = min(0.35, max(0.15, (y2 - y1) / 135))
        (tw, th), _ = cv2.getTextSize( label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, 1 )
        cv2.rectangle(img, (x1, max(0, y1 - th - 6)), (x1 + tw, y1), (0, 255, 0), -1, )
        cv2.putText(
            img,
            label,
            (x1, max(15, y1 - 5)),
            cv2.FONT_HERSHEY_SIMPLEX,
            font_scale,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(out_path, img)

def main():
    args = build_parser().parse_args()

    model = load_model(args.model, DEFAULT_DEVICE)

    pred = run_sahi(
        model,
        args.image,
        args.slice_size,
        args.overlap,
    )

    save_txt(pred, args.image, args.out_txt)

    if args.visualize:
        visualize(args.image, pred, args.out_img)

    print(f"Saved TXT: {args.out_txt}")
    print(f"Detections: {len(pred.object_prediction_list)}")


if __name__ == "__main__":
    main()