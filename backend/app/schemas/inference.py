from typing import List, Literal, Optional
from uuid import UUID
from pydantic import BaseModel, Field

class InferenceRequest(BaseModel):
    image_id: UUID
    lang: Optional[Literal["en", "np"]] = Field(default="en")


class Annotations(BaseModel):
    class_id: int
    x1: float
    y1: float
    x2: float
    y2: float

class InferenceResponse(BaseModel):
    extracted_text: str
    annotations: List[Annotations]