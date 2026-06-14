from typing import List

import numpy as np

from ..schemas import DetectedCharacter
from .braille_mapper import apply_braille_rules


def _group_into_lines(
    detections: List[DetectedCharacter],
    line_threshold: int,
) -> List[List[DetectedCharacter]]:
    detections = sorted(detections, key=lambda d: d.y)

    lines: List[List[DetectedCharacter]] = []
    current_line: List[DetectedCharacter] = []
    current_y: float | None = None

    for det in detections:
        if current_y is None:
            current_line = [det]
            current_y = det.y
        elif abs(det.y - current_y) <= line_threshold:
            current_line.append(det)
        else:
            lines.append(sorted(current_line, key=lambda d: d.x))
            current_line = [det]
            current_y = det.y

    if current_line:
        lines.append(sorted(current_line, key=lambda d: d.x))

    return lines


def _reconstruct_text_line_with_space(line: List[DetectedCharacter]) -> str:
    if not line:
        return ""

    gaps = [
        line[i + 1].x_min - line[i].x_max
        for i in range(len(line) - 1)
    ]

    space_threshold = (np.mean(gaps) + np.std(gaps)) if gaps else 0

    text = ""

    for i, det in enumerate(line):
        text += det.character

        if (
            i < len(line) - 1
            and (line[i + 1].x_min - line[i].x_max) > space_threshold
        ):
            text += " "

    return text


def convert_detections_to_text(
    prediction_result,
    label_map: dict[int, str],
    confidence_threshold: float = 0.4,
    line_threshold: int = 25,
) -> str:
    if prediction_result is None:
        return ""

    detections: List[DetectedCharacter] = []

    for obj in prediction_result.object_prediction_list:
        if obj.score.value < confidence_threshold:
            continue

        detections.append(
            DetectedCharacter(
                x_min=int(obj.bbox.minx),
                y_min=int(obj.bbox.miny),
                x_max=int(obj.bbox.maxx),
                y_max=int(obj.bbox.maxy),
                confidence=obj.score.value,
                class_id=obj.category.id,
                character=label_map.get(
                    obj.category.id,
                    f"[{obj.category.id}]",
                ),
            )
        )

    if not detections:
        return ""

    lines = _group_into_lines(detections, line_threshold)

    processed_lines = [
        apply_braille_rules(_reconstruct_text_line_with_space(line))
        for line in lines
    ]

    return "\n".join(processed_lines)