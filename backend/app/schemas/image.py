from datetime import datetime
from uuid import UUID
from pydantic import BaseModel, ConfigDict 

class ImageResponse(BaseModel):
    id: UUID
    image_path: str
    uploaded_at: datetime

    model_config = ConfigDict(
        from_attributes = True
    )