from types import SimpleNamespace

from vision.inference.conversion.text_construction import convert_detections_to_text
from vision.inference.processing.postprocess import apply_global_nms


class FakeBBox:
    def __init__(self, minx: float, miny: float, maxx: float, maxy: float):
        self.minx = minx
        self.miny = miny
        self.maxx = maxx
        self.maxy = maxy

    def to_xyxy(self):
        return [self.minx, self.miny, self.maxx, self.maxy]


class FakeScore:
    def __init__(self, value: float):
        self.value = value


class FakeCategory:
    def __init__(self, class_id: int):
        self.id = class_id


def _make_prediction(minx, miny, maxx, maxy, score, class_id=0):
    return SimpleNamespace(
        bbox=FakeBBox(minx, miny, maxx, maxy),
        score=FakeScore(score),
        category=FakeCategory(class_id),
    )


def _make_prediction_result(predictions):
    return SimpleNamespace(object_prediction_list=list(predictions))


def test_overlapping_boxes_are_removed_by_nms():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(0, 0, 10, 10, 0.95),
            _make_prediction(1, 1, 11, 11, 0.90),
        ]
    )

    filtered_result, removed = apply_global_nms(prediction_result, iou_threshold=0.1)

    assert removed == 1
    assert len(filtered_result.object_prediction_list) == 1
    assert filtered_result.object_prediction_list[0].score.value == 0.95


def test_non_overlapping_boxes_are_preserved_by_nms():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(0, 0, 10, 10, 0.95),
            _make_prediction(20, 20, 30, 30, 0.90),
        ]
    )

    filtered_result, removed = apply_global_nms(prediction_result, iou_threshold=0.1)

    assert removed == 0
    assert len(filtered_result.object_prediction_list) == 2


def test_confidence_threshold_filters_low_confidence_detections():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(0, 0, 10, 10, 0.40, class_id=0),
            _make_prediction(20, 0, 30, 10, 0.80, class_id=1),
        ]
    )

    text = convert_detections_to_text(
        prediction_result,
        label_map={0: "A", 1: "B"},
        confidence_threshold=0.5,
    )

    assert text == "B"


def test_empty_detections_return_empty_text():
    prediction_result = _make_prediction_result([])

    text = convert_detections_to_text(prediction_result, label_map={0: "A"})

    assert text == ""


def test_single_detection_is_converted_to_text():
    prediction_result = _make_prediction_result(
        [_make_prediction(0, 0, 10, 10, 0.90, class_id=0)]
    )

    text = convert_detections_to_text(prediction_result, label_map={0: "A"})

    assert text == "A"
