from datetime import datetime, timezone
from sqlmodel import SQLModel, Field

class Image(SQLModel, table=True):
    id: int = Field(default=None, primary_key=True)
    user_id: str
    image_path: str
    uploaded_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
