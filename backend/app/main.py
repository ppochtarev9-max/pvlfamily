from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from . import models
from .database import engine
from .auth import router as auth_router
from .budget import router as budget_router
from .calendar import router as calendar_router

models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="PVLFamily API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/auth", tags=["Auth"])
app.include_router(budget_router, prefix="/budget", tags=["Budget"])
app.include_router(calendar_router, prefix="/calendar", tags=["Calendar"])

@app.get("/health")
def health():
    return {"status": "ok", "message": "Backend is running"}
