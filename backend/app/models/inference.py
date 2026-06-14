from datetime import datetime, timezone
from uuid import UUID, uuid4
from sqlmodel import SQLModel, Field
from sqlalchemy import Column
from sqlalchemy.dialects.postgresql import JSONB

class InferenceResult(SQLModel, table=True):
    id: UUID = Field(default_factory=uuid4, primary_key=True)    
    image_id: UUID = Field(foreign_key="image.id")
    extracted_text: str
    lang: str = Field(default="en")
    annotations: list[dict] = Field(sa_column=Column(JSONB))
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))