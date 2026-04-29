from pathlib import Path
import cv2
import numpy as np
import torch
from torchvision.ops import nms
from sahi import AutoDetectionModel
from sahi.predict import get_sliced_prediction
import yaml

BASE_DIR = Path(__file__).resolve().parent.parent.parent

with open("configs/model/characters.yaml", "r") as f:
    data = yaml.safe_load(f)

BRAILLE_DICT = {v: k for k, v in data["names"].items()}
ID_TO_BRAILLE = data["names"]

DEFAULT_SAHI_CONFIG = {
    "slice_size":                  640,
    "overlap_ratio":               0.1,
    "postprocess_type":            "NMM",
    "postprocess_match_metric":    "IOU",
    "postprocess_match_threshold": 0.5,
    "confidence_threshold":        0.4,
    "device":                      "cuda" if torch.cuda.is_available() else "cpu",
}

def load_model(model_path: str, config: dict = None):
    cfg = {**DEFAULT_SAHI_CONFIG, **(config or {})}
    model_path = Path(model_path)

    if not model_path.exists():
        raise FileNotFoundError(f"Model not found: {model_path}")

    return AutoDetectionModel.from_pretrained(
        model_type="ultralytics",
        model_path=str(model_path),
        confidence_threshold=cfg["confidence_threshold"],
        device=cfg["device"],
    )


def _apply_global_nms(prediction_result, iou_thresh: float = 0.1):
    preds = prediction_result.object_prediction_list
    if not preds:
        return prediction_result
    boxes  = torch.tensor(
        [p.bbox.to_xyxy() for p in preds],
        dtype=torch.float32
    )
    scores = torch.tensor(
        [p.score.value for p in preds],
        dtype=torch.float32
    )
    keep   = nms(boxes, scores, iou_thresh)
    prediction_result.object_prediction_list = [preds[i] for i in keep]
    return prediction_result


def run_sahi_inference(model, image_path: str, config: dict = None):
    cfg = {**DEFAULT_SAHI_CONFIG, **(config or {})}

    prediction_result = get_sliced_prediction(
        image=str(image_path),
        detection_model=model,
        slice_height=cfg["slice_size"],
        slice_width=cfg["slice_size"],
        overlap_height_ratio=cfg["overlap_ratio"],
        overlap_width_ratio=cfg["overlap_ratio"],
        postprocess_type=cfg["postprocess_type"],
        postprocess_match_metric=cfg["postprocess_match_metric"],
        postprocess_match_threshold=cfg["postprocess_match_threshold"],
        verbose=False,
    )
    return _apply_global_nms(prediction_result, iou_thresh=0.1)
    # return prediction_result

def convert_detections_to_text(
    prediction_result,
    confidence_threshold: float = 0.4,
    line_threshold:       int   = 25,
):
    if prediction_result is None:
        return {"text": "", "lines": [], "characters": [], "total_detected": 0, "converted": 0}

    candidates = []
    areas      = []

    for obj in prediction_result.object_prediction_list:
        if obj.score.value < confidence_threshold:
            continue

        class_id        = obj.category.id
        mapped_class_id = class_id 
        character       = BRAILLE_DICT.get(mapped_class_id, f"[{mapped_class_id}]")

        width  = obj.bbox.maxx - obj.bbox.minx
        height = obj.bbox.maxy - obj.bbox.miny
        area   = width * height

        candidates.append({
            "x_min":    int(obj.bbox.minx),
            "y_min":    int(obj.bbox.miny),
            "x_max":    int(obj.bbox.maxx),
            "y_max":    int(obj.bbox.maxy),
            "x":        (obj.bbox.minx + obj.bbox.maxx) / 2,
            "y":        (obj.bbox.miny + obj.bbox.maxy) / 2,
            "confidence": obj.score.value,
            "class_id": class_id,
            "character": character,
            "width":    width,
            "height":   height,
            "area":     area,
        })
        areas.append(area)

    if areas:
        q1, q3           = np.percentile(areas, [25, 75])
        iqr              = q3 - q1
        max_area         = min(q3 + 1.5 * iqr, 2000)
        detections       = [d for d in candidates if d["area"] <= max_area]
    else:
        detections = candidates

    if not detections:
        return {"text": "", "lines": [], "characters": [], "total_detected": 0, "converted": 0}

    detections.sort(key=lambda d: d["y"])
    lines, current_line, current_y = [], [], None

    for det in detections:
        if current_y is None or abs(det["y"] - current_y) <= line_threshold:
            current_line.append(det)
            current_y = det["y"] if current_y is None else current_y
        else:
            lines.append(sorted(current_line, key=lambda d: d["x"]))
            current_line = [det]
            current_y    = det["y"]

    if current_line:
        lines.append(sorted(current_line, key=lambda d: d["x"]))

    text_lines = []
    for line in lines:
        gaps = [line[i+1]["x_min"] - line[i]["x_max"] for i in range(len(line) - 1)]
        space_thresh = (np.mean(gaps) + np.std(gaps)) if gaps else 0

        line_text = ""
        for i, d in enumerate(line):
            line_text += d["character"]
            if i < len(line) - 1 and (line[i+1]["x_min"] - line[i]["x_max"]) > space_thresh:
                line_text += " "
        text_lines.append(line_text)

    def apply_braille_rules(text_line: str) -> str:
        i, output, upper_mode, number_mode = 0, "", False, False
        while i < len(text_line):
            if text_line.startswith("[CAPS][CAPS]", i):
                upper_mode = True
                i += len("[CAPS][CAPS]")
            elif text_line.startswith("[CAPS]", i):
                i += len("[CAPS]")
                if i < len(text_line):
                    output += text_line[i].upper()
                    i += 1
            elif text_line.startswith("[NUMBER]", i):
                number_mode = True
                i += len("[NUMBER]")
            else:
                ch = text_line[i]
                if ch in " ,.;:!?-()\"'":
                    number_mode = upper_mode = False
                    output += ch
                elif number_mode and ch.isalpha():
                    num_map = {'a':'1','b':'2','c':'3','d':'4','e':'5',
                               'f':'6','g':'7','h':'8','i':'9','j':'0'}
                    if ch.lower() in num_map:
                        output += num_map[ch.lower()]
                    else:
                        number_mode = False
                        output += ch.upper() if upper_mode else ch
                else:
                    output += ch.upper() if upper_mode else ch
                i += 1
        return output

    processed_lines = [apply_braille_rules(l) for l in text_lines]

    return {
        "text":           "\n".join(processed_lines),
        "lines":          processed_lines,
        "characters":     detections,
        "total_detected": len(prediction_result.object_prediction_list),
        "converted":      len(detections),
    }


def create_visualization(
    image_path: str,
    detections: list,
    output_path: str = None,
    show_bboxes: bool = True,
):
    img = cv2.imread(str(image_path))
    if img is None:
        raise FileNotFoundError(f"Could not load image: {image_path}")

    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)

    for det in detections:
        x1, y1, x2, y2 = (
            det["x_min"],
            det["y_min"],
            det["x_max"],
            det["y_max"],
        )

        # Convert class_id → braille binary string
        class_id = det["class_id"]
        label = ID_TO_BRAILLE.get(class_id, str(class_id))

        if show_bboxes:
            cv2.rectangle(img_rgb, (x1, y1), (x2, y2), (0, 255, 0), 2)

        # font scaling based on box size
        font_scale = max(0.4, (y2 - y1) / 120)

        (tw, th), _ = cv2.getTextSize(
            label, cv2.FONT_HERSHEY_SIMPLEX, font_scale, 1
        )

        # background box for readability
        cv2.rectangle(
            img_rgb,
            (x1, max(0, y1 - th - 6)),
            (x1 + tw, y1),
            (0, 255, 0),
            -1,
        )

        # braille binary label
        cv2.putText(
            img_rgb,
            label,
            (x1, max(15, y1 - 5)),
            cv2.FONT_HERSHEY_SIMPLEX,
            font_scale,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )

    if output_path:
        cv2.imwrite(
            str(output_path),
            cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR),
        )

    return img_rgb


def run_inference(
    model_path:           str,
    image_path:           str,
    output_path:          str   = None,
    config:               dict  = None,
    confidence_threshold: float = 0.4,
    line_threshold:       int   = 25,
    show_characters:      bool  = True,
    show_bboxes:          bool  = True,
):
    model            = load_model(model_path, config)
    prediction_result = run_sahi_inference(model, image_path, config)
    result           = convert_detections_to_text(prediction_result, confidence_threshold, line_threshold)
    annotated        = create_visualization(image_path, result["characters"], output_path, show_bboxes)
    result["annotated_image"] = annotated
    return result


if __name__ == "__main__":
    print(BASE_DIR)
    result = run_inference(
        model_path= BASE_DIR / "runs/train-4/weights/best.pt",
        image_path = BASE_DIR / "data/WhatsApp Image 2026-04-29 at 4.36.36 PM.jpeg",
        output_path=BASE_DIR/ "data/output/output5.jpg",
        # config={"slice_size": 640, "confidence_threshold": 0.4},
    )
    print(f"Detected text:\n{result['text']}")
    print(f"Total detections : {result['total_detected']}")
    print(f"After filtering  : {result['converted']}")