from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from . import models
from .database import engine
from .auth import router as auth_router
from .budget import router as budget_router
from .calendar import router as calendar_router
from .stats import router as stats_router
from .tracker import router as tracker_router  # <--- ДОБАВИТЬ

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
app.include_router(stats_router, prefix="/dashboard", tags=["Dashboard"])
app.include_router(tracker_router, prefix="/tracker", tags=["Tracker"])  # <--- ДОБАВИТЬ

@app.get("/health")
def health():
    return {"status": "ok", "message": "Backend is running"}