from types import SimpleNamespace

from vision.inference.conversion.text_construction import convert_detections_to_text


class FakeBBox:
    def __init__(self, minx: float, miny: float, maxx: float, maxy: float):
        self.minx = minx
        self.miny = miny
        self.maxx = maxx
        self.maxy = maxy


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


def test_braille_mapping_uses_label_map_for_characters():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(0, 0, 5, 5, 0.95, class_id=0),
            _make_prediction(10, 0, 15, 5, 0.90, class_id=1),
        ]
    )

    text = convert_detections_to_text(
        prediction_result,
        label_map={0: "A", 1: "B"},
        confidence_threshold=0.5,
    )

    assert text == "AB"


def test_line_ordering_sorts_detections_left_to_right_within_a_line():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(20, 0, 25, 5, 0.95, class_id=1),
            _make_prediction(0, 0, 5, 5, 0.90, class_id=0),
        ]
    )

    text = convert_detections_to_text(
        prediction_result,
        label_map={0: "A", 1: "B"},
        confidence_threshold=0.5,
    )

    assert text == "AB"


def test_multi_line_reconstruction_separates_detections_by_vertical_position():
    prediction_result = _make_prediction_result(
        [
            _make_prediction(0, 0, 5, 5, 0.95, class_id=0),
            _make_prediction(0, 40, 5, 45, 0.90, class_id=1),
        ]
    )

    text = convert_detections_to_text(
        prediction_result,
        label_map={0: "A", 1: "B"},
        confidence_threshold=0.5,
        line_threshold=25,
    )

    assert text == "A\nB"
