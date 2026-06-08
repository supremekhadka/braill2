from datetime import datetime, timezone
from sqlmodel import SQLModel, Field

class InferenceResult(SQLModel, table=True):
    id: int = Field(default=None, primary_key=True)
    user_id: str
    image_id: int
    extracted_text: str
    annotated_image_path: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))