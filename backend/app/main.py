from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import SQLModel

from backend.app.core.database import engine
from backend.app.api import auth, image, inference, users

@asynccontextmanager
async def lifespan(app: FastAPI):
    SQLModel.metadata.create_all(bind=engine)
    yield
    engine.dispose()

app = FastAPI(title="Braill.", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(auth.auth_router)
app.include_router(image.image_router)
app.include_router(inference.inference_router)
app.include_router(users.user_router)