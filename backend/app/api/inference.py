from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from backend.app.schemas.inference import InferenceRequest, InferenceResponse
from backend.app.models.user import User
from backend.app.services.inference import run_inference_service, get_prediction_history
from backend.app.api.dependencies import get_current_user
from backend.app.core.database import get_session
from backend.app.core.configs import InferenceConfig

inference_router = APIRouter(tags=["Inference"], prefix="/api/inference")

@inference_router.post(
        "/predict", 
        response_model=InferenceResponse,
        dependencies=[Depends(get_current_user)]
)
async def predict(
    payload: InferenceRequest,
    session: Annotated[Session, Depends(get_session)]
):
    if payload.lang not in InferenceConfig.ALLOWED_LANGS:
        raise HTTPException(status_code=400, detail="Unsupported language")

    result = run_inference_service(session=session, image_id=payload.image_id, lang=payload.lang)

    return result


@inference_router.get(
    "/history",
    response_model=list[InferenceResponse]
)
async def prediction_history(
    session: Annotated[Session, Depends(get_session)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    return get_prediction_history(
        session=session,
        user_id=current_user.id
    )