import json
import logging
import os
import time
from typing import Any, Dict, List, Optional

import motor.motor_asyncio
from fastapi import Body, FastAPI, HTTPException, status
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache
from logmiddleware import RouterLoggingMiddleware, logging_config
from pydantic import BaseModel, Field
from pydantic.functional_validators import BeforeValidator
from pymongo import errors
from redis import asyncio as aioredis
from typing_extensions import Annotated

logging.config.dictConfig(logging_config)
logger = logging.getLogger(__name__)

app = FastAPI()
app.add_middleware(
    RouterLoggingMiddleware,
    logger=logger,
)

DATABASE_URL = os.environ["MONGODB_URL"]
DATABASE_NAME = os.environ["MONGODB_DATABASE_NAME"]
REDIS_URL = os.getenv("REDIS_URL", None)


def nocache(*args, **kwargs):
    def decorator(func):
        return func

    return decorator


if REDIS_URL:
    cache = cache
else:
    cache = nocache


client = motor.motor_asyncio.AsyncIOMotorClient(DATABASE_URL)
db = client[DATABASE_NAME]

PyObjectId = Annotated[str, BeforeValidator(str)]


@app.on_event("startup")
async def startup():
    if REDIS_URL:
        redis = aioredis.from_url(REDIS_URL, encoding="utf8", decode_responses=True)
        FastAPICache.init(RedisBackend(redis), prefix="api:cache")


async def hello_doc_shard_counts() -> Optional[Dict[str, int]]:
    try:
        stats: Dict[str, Any] = await db.command("collStats", "helloDoc")
    except errors.OperationFailure:
        return None
    if not stats.get("sharded"):
        return None
    out: Dict[str, int] = {}
    for shard_id, shard_stats in stats.get("shards", {}).items():
        if isinstance(shard_stats, dict):
            cnt = shard_stats.get("count")
            if cnt is None and isinstance(shard_stats.get("storageStats"), dict):
                cnt = shard_stats["storageStats"].get("count")
            if cnt is not None:
                out[str(shard_id)] = int(cnt)
    return out or None


def shard_replica_info_from_list_shards(shards_list: Dict[str, Any]) -> Dict[str, Dict[str, int]]:
    """
    Из ответа listShards: host вида name/host1:port,host2:port — число узлов RS и secondaries.
    """
    out: Dict[str, Dict[str, int]] = {}
    for shard in shards_list.get("shards", []):
        sid = str(shard.get("_id", ""))
        host = str(shard.get("host", ""))
        if "/" in host:
            _, rest = host.split("/", 1)
            members = [m.strip() for m in rest.split(",") if m.strip()]
            n = len(members)
            out[sid] = {
                "members": n,
                "secondaries": max(0, n - 1),
            }
        else:
            out[sid] = {"members": 1, "secondaries": 0}
    return out


class UserModel(BaseModel):
    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    age: int = Field(...)
    name: str = Field(...)


class UserCollection(BaseModel):
    users: List[UserModel]


@app.get("/")
async def root():
    collection_names = await db.list_collection_names()
    collections = {}
    for collection_name in collection_names:
        collection = db.get_collection(collection_name)
        entry: Dict[str, Any] = {
            "documents_count": await collection.count_documents({}),
        }
        if collection_name == "helloDoc":
            per_shard = await hello_doc_shard_counts()
            if per_shard is not None:
                entry["documents_per_shard"] = per_shard
        collections[collection_name] = entry
    try:
        replica_status = await client.admin.command("replSetGetStatus")
        replica_status = json.dumps(replica_status, indent=2, default=str)
    except errors.OperationFailure:
        replica_status = "No Replicas"

    topology_description = client.topology_description
    read_preference = client.client_options.read_preference
    topology_type = topology_description.topology_type_name
    replicaset_name = topology_description.replica_set_name

    shards = None
    shard_replica_sets: Optional[Dict[str, Dict[str, int]]] = None
    if topology_type == "Sharded":
        shards_list = await client.admin.command("listShards")
        shards = {}
        for shard in shards_list.get("shards", []):
            shards[shard["_id"]] = shard["host"]
        shard_replica_sets = shard_replica_info_from_list_shards(shards_list)

    cache_enabled = False
    if REDIS_URL:
        cache_enabled = FastAPICache.get_enable()

    # Подключение к mongos: replSetGetStatus недоступен — репликация шардов смотрится в shard_replica_sets и в поле shards (три хоста в строке на шард).
    return {
        "mongo_topology_type": topology_type,
        "mongo_replicaset_name": replicaset_name,
        "mongo_db": DATABASE_NAME,
        "read_preference": str(read_preference),
        "mongo_nodes": client.nodes,
        "mongo_primary_host": client.primary,
        "mongo_secondary_hosts": client.secondaries,
        "mongo_is_primary": client.is_primary,
        "mongo_is_mongos": client.is_mongos,
        "collections": collections,
        "shards": shards,
        "shard_replica_sets": shard_replica_sets,
        "cache_enabled": cache_enabled,
        "status": "OK",
    }


@app.get("/{collection_name}/count")
async def collection_count(collection_name: str):
    collection = db.get_collection(collection_name)
    items_count = await collection.count_documents({})
    return {"status": "OK", "mongo_db": DATABASE_NAME, "items_count": items_count}


@app.get(
    "/{collection_name}/users",
    response_description="List all users",
    response_model=UserCollection,
    response_model_by_alias=False,
)
@cache(expire=60 * 1)
async def list_users(collection_name: str):
    time.sleep(1)
    collection = db.get_collection(collection_name)
    return UserCollection(users=await collection.find().to_list(1000))


@app.get(
    "/{collection_name}/users/{name}",
    response_description="Get a single user",
    response_model=UserModel,
    response_model_by_alias=False,
)
async def show_user(collection_name: str, name: str):
    collection = db.get_collection(collection_name)
    if (user := await collection.find_one({"name": name})) is not None:
        return user

    raise HTTPException(status_code=404, detail=f"User {name} not found")


@app.post(
    "/{collection_name}/users",
    response_description="Add new user",
    response_model=UserModel,
    status_code=status.HTTP_201_CREATED,
    response_model_by_alias=False,
)
async def create_user(collection_name: str, user: UserModel = Body(...)):
    collection = db.get_collection(collection_name)
    new_user = await collection.insert_one(
        user.model_dump(by_alias=True, exclude=["id"])
    )
    created_user = await collection.find_one({"_id": new_user.inserted_id})
    return created_user
