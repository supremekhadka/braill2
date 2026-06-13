from dataclasses import dataclass

@dataclass
class DetectionBox:
    id: int
    x_min: int
    y_min: int
    x_max: int
    y_max: int
    width: int
    height: int
    confidence: float
    area: int


from dataclasses import dataclass


@dataclass
class DetectedCharacter:
    x_min: int
    y_min: int
    x_max: int
    y_max: int

    confidence: float
    class_id: int
    character: str

    @property
    def x(self) -> float:
        return (self.x_min + self.x_max) / 2

    @property
    def y(self) -> float:
        return (self.y_min + self.y_max) / 2

    @property
    def width(self) -> float:
        return self.x_max - self.x_min

    @property
    def height(self) -> float:
        return self.y_max - self.y_min

    @property
    def area(self) -> float:
        return self.width * self.height
    