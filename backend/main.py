import uuid
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Query
from typing import Annotated, Optional
from sqlmodel import Field, Session, SQLModel, create_engine, select 

# class definitions
class User(SQLModel, table=True):
    id: Optional[str] = Field(default_factory=lambda: str(uuid.uuid4()), primary_key=True)
    name: str = Field(index=True)

class Detection(SQLModel, table=True):
    id: Optional[str] = Field(default_factory=lambda: str(uuid.uuid4()), primary_key=True)
    userId: str = Field(foreign_key="user.id")
    imageId: str = Field(foreign_key="image.id")
    detections: str = Field(default="{}", index=True)

psql_url = "postgresql://postgres:postgres@localhost:5432/braill2"

engine = create_engine(psql_url)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session

SessionDep = Annotated[Session, Depends(get_session)]

@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield
    

app = FastAPI(lifespan=lifespan)

@app.post("/detections/")
def create_detection(detection: Detection, session: SessionDep) -> Detection:
    session.add(detection)
    session.commit()
    session.refresh(detection)
    return detection

@app.get("/detections/")
def get_detections(session:SessionDep, offset: int = 0, limit: Annotated[int, Query(le=100)] = 99999) -> list[Detection]:
    detections = session.exec(select(Detection).offset(offset).limit(limit)).all()
    return detections

@app.get("/")
def read_root():
    return {"Hello": "World"}

