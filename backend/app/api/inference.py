from typing import Annotated
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session

from backend.app.schemas.inference import (
    InferenceRequest,
    InferenceResponse,
    BatchInferenceRequest,
    BatchInferenceResponse,
)
from backend.app.models.user import User
from backend.app.services.inference import (
    run_inference_service,
    run_batch_inference_service,
    get_prediction_history,
    delete_prediction_service
)
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


@inference_router.post(
    "/predict/batch",
    response_model=BatchInferenceResponse,
    dependencies=[Depends(get_current_user)]
)
async def predict_batch(
    payload: BatchInferenceRequest,
    session: Annotated[Session, Depends(get_session)]
):
    if payload.lang not in InferenceConfig.ALLOWED_LANGS:
        raise HTTPException(status_code=400, detail="Unsupported language")

    if not payload.image_ids:
        raise HTTPException(status_code=400, detail="image_ids must not be empty")

    if len(payload.image_ids) > InferenceConfig.BATCH_SIZE:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot process more than {InferenceConfig.BATCH_SIZE} images per batch",
        )

    try:
        results = run_batch_inference_service(
            session=session, image_ids=payload.image_ids, lang=payload.lang
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    return {"results": results}


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

@inference_router.delete(
    "/history/{prediction_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_history_entry(
    prediction_id: UUID,
    session: Annotated[Session, Depends(get_session)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    try:
        delete_prediction_service(
            session=session, prediction_id=prediction_id, user_id=current_user.id
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))