import argparse

from .pipeline import pipeline
from .utils.file_utils import write_text, write_image
from .utils.visualization import render_from_json

INFERENCE_CONFIG = {
    "model": "weights/deployment/best_finetuned_mAP_96_1.pt",
    "image": "path/to/image",
    "out_text": "data/output/text.txt",
    "out_img": "data/output/vis.jpg",
    "slice_size": 640,
    "overlap": 0.1,
    "confidence": 0.4,
    "nms_iou": 0.1,
    "label_mode": "en",
    "binary_map": "configs/data.yaml",
    "braille_map": "configs/braille.yaml",
    "label_map": "configs/braille.yaml"
}


def build_parser():
    p = argparse.ArgumentParser()

    p.add_argument("--model", type=str, default=INFERENCE_CONFIG["model"])
    p.add_argument("--image", type=str, default=INFERENCE_CONFIG["image"])

    p.add_argument("--out-text", type=str, default=INFERENCE_CONFIG["out_text"])
    p.add_argument("--out-img", type=str, default=INFERENCE_CONFIG["out_img"])

    p.add_argument("--slice-size", type=int, default=INFERENCE_CONFIG["slice_size"])
    p.add_argument("--overlap", type=float, default=INFERENCE_CONFIG["overlap"])
    p.add_argument("--confidence", type=float, default=INFERENCE_CONFIG["confidence"])
    p.add_argument("--nms-iou", type=float, default=INFERENCE_CONFIG["nms_iou"])

    p.add_argument(
        "--label-mode",
        type=str,
        choices=["en", "binary"],
        default=INFERENCE_CONFIG["label_mode"],
    )

    p.add_argument("--visualize", action="store_true")

    p.add_argument("--label-map", type=str, default=INFERENCE_CONFIG["label_map"])

    return p

def main():
    args = build_parser().parse_args()

    cfg = {
        "model": args.model,
        "slice_size": args.slice_size,
        "overlap": args.overlap,
        "confidence": args.confidence,
        "nms_iou": args.nms_iou,
        "label_map": args.label_map
    }

    result = pipeline(args.image, cfg)

    write_text(args.out_text, result['extracted_text'])

    if args.visualize:
        img = render_from_json(
            args.image, 
            result['annotations'],
            INFERENCE_CONFIG["braille_map"] if args.label_mode=="en" else INFERENCE_CONFIG["binary_map"]
        )
        write_image(args.out_img, img)

    print(f"Raw detections: {result['raw_detections']}")
    print(f"Area outliers removed: {result['outliers_removed']}")
    print(f"NMS duplicates removed: {result['nms_removed']}")
    print(f"Final detections: {result['raw_detections'] - result['outliers_removed'] - result['nms_removed']}")


if __name__ == "__main__":
    main()