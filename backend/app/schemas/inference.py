from datetime import datetime
from typing import List, Literal, Optional
from uuid import UUID
from pydantic import BaseModel, Field
class InferenceRequest(BaseModel):
    image_id: UUID
    lang: Optional[Literal["en", "np", "unicode"]] = Field(default="en")
class Annotations(BaseModel):
    class_id: int
    x1: float
    y1: float
    x2: float
    y2: float
class InferenceResponse(BaseModel):
    id: UUID
    image_id: UUID
    extracted_text: str
    annotations: List[Annotations]
    # Added so clients (e.g. the mobile history screen) can sort a combined
    # online + offline history list by date without a second round trip.
    created_at: datetime
class BatchInferenceRequest(BaseModel):
    image_ids: list[UUID]
    lang: Optional[Literal["en", "np", "unicode"]] = Field(default="en")
 
 
class BatchInferenceResultItem(InferenceResponse):
    image_id: UUID
 
 
class BatchInferenceResponse(BaseModel):
    results: list[BatchInferenceResultItem]