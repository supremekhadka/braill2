import filetype
import json
import struct
from pathlib import Path
import yaml

def load_label_map(config_path: str) -> dict[int, str]:
    with open(config_path, "r") as f:
        data = yaml.safe_load(f)
    return {int(k): v for k, v in data.items()}

def image_dimensions(image_path: str) -> tuple[int, int]:
    """
    Return (height, width) without decoding pixel data where possible.
    Reads only the header bytes for PNG and JPEG.
    """
    kind = filetype.guess(image_path)

    if kind == "png":
        with open(image_path, "rb") as f:
            f.seek(16)
            w, h = struct.unpack(">II", f.read(8))
        return h, w

    if kind in ("jpeg", "jpg"):
        with open(image_path, "rb") as f:
            f.read(2)
            while True:
                marker, = struct.unpack(">H", f.read(2))
                size, = struct.unpack(">H", f.read(2))
                if marker in (0xFFC0, 0xFFC2):
                    f.read(1)
                    h, w = struct.unpack(">HH", f.read(4))
                    return h, w
                f.read(size - 2)

    import cv2
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Cannot read image: {image_path}")
    return img.shape[:2]


def write_text(path: str, content: str, encoding: str = "utf-8") -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding=encoding)


def write_json(path: str, data: list | dict) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, "w") as f:
        json.dump(data, f, indent=2)


def write_image(path: str, img) -> None:
    import cv2
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(p), img)