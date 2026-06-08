from datetime import datetime
from pydantic import BaseModel, ConfigDict 

class ImageResponse(BaseModel):
    id: int
    user_id: str
    image_path: str
    uploaded_at: datetime

    model_config = ConfigDict(
        from_attributes = True
    )