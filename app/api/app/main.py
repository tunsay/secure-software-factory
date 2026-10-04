"""API FastAPI minimale : /health, /items (CRUD en mémoire), /metrics.

L'application est volontairement triviale. Sa seule raison d'être est de servir
de cible à la chaîne de build, de scan et de déploiement autour d'elle.
"""

from __future__ import annotations

import os
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")
APP_ENV = os.getenv("APP_ENV", "local")
CORS_ORIGINS = [o for o in os.getenv("CORS_ORIGINS", "").split(",") if o]


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    quantity: int = Field(ge=0, le=10_000)


class Item(ItemIn):
    id: UUID


# /docs et /openapi.json ne sont jamais servis au public : nginx les refuse en bordure (jalon 6a).
# En prod, ils n'existent pas du tout : la carte de l'API n'est pas offerte.
app = FastAPI(
    title="Secure Software Factory — API",
    version=APP_VERSION,
    docs_url="/docs" if APP_ENV != "prod" else None,
    openapi_url="/openapi.json" if APP_ENV != "prod" else None,
    redoc_url=None,
)


@app.exception_handler(RequestValidationError)
async def validation_error(_request: Request, exc: RequestValidationError) -> JSONResponse:
    """Erreur 422 sans la valeur reçue : ne jamais renvoyer au client ce qu'il a envoyé.

    Par défaut, FastAPI recopie l'entrée invalide dans la réponse (champ « input ») : une
    réflexion d'entrée, trouvée par make dast au jalon 6a. On garde le champ en cause et la
    raison, pas la valeur.
    """
    detail = [
        {"type": err["type"], "loc": list(err["loc"]), "msg": err["msg"]} for err in exc.errors()
    ]
    # 422 en clair : le nom de la constante a changé entre versions de Starlette.
    return JSONResponse(status_code=422, content={"detail": detail})


if CORS_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_ORIGINS,
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["Content-Type"],
    )

Instrumentator(excluded_handlers=["/health", "/metrics"]).instrument(app).expose(
    app, endpoint="/metrics", include_in_schema=False
)

# Stockage en mémoire : perdu au redémarrage, et c'est voulu.
_items: dict[UUID, Item] = {}


@app.get("/health", include_in_schema=False)
def health() -> dict[str, str]:
    return {"status": "ok", "version": APP_VERSION, "env": APP_ENV}


@app.get("/items", response_model=list[Item])
def list_items() -> list[Item]:
    return list(_items.values())


@app.post("/items", response_model=Item, status_code=status.HTTP_201_CREATED)
def create_item(payload: ItemIn) -> Item:
    item = Item(id=uuid4(), **payload.model_dump())
    _items[item.id] = item
    return item


@app.get("/items/{item_id}", response_model=Item)
def get_item(item_id: UUID) -> Item:
    try:
        return _items[item_id]
    except KeyError:
        raise HTTPException(status_code=404, detail="item not found") from None


@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, response_class=Response)
def delete_item(item_id: UUID) -> Response:
    if _items.pop(item_id, None) is None:
        raise HTTPException(status_code=404, detail="item not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
