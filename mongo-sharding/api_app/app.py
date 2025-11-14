import json
import logging
import os
import time
from typing import List, Optional

import motor.motor_asyncio
from bson import ObjectId
from fastapi import Body, FastAPI, HTTPException, status
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache
from logmiddleware import RouterLoggingMiddleware, logging_config
from pydantic import BaseModel, ConfigDict, EmailStr, Field
from pydantic.functional_validators import BeforeValidator
from pymongo import errors
from redis import asyncio as aioredis
from typing_extensions import Annotated

# Configure JSON logging
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

# Represents an ObjectId field in the database.
# It will be represented as a `str` on the model so that it can be serialized to JSON.
PyObjectId = Annotated[str, BeforeValidator(str)]


@app.on_event("startup")
async def startup():
    if REDIS_URL:
        redis = aioredis.from_url(REDIS_URL, encoding="utf8", decode_responses=True)
        FastAPICache.init(RedisBackend(redis), prefix="api:cache")


class UserModel(BaseModel):
    """
    Container for a single user record.
    """

    id: Optional[PyObjectId] = Field(alias="_id", default=None)
    age: int = Field(...)
    name: str = Field(...)


class UserCollection(BaseModel):
    """
    A container holding a list of `UserModel` instances.
    """

    users: List[UserModel]


@app.get("/")
async def root():
    # Получаем общее количество документов в базе
    total_documents = 0
    collection_names = await db.list_collection_names()
    collections = {}
    for collection_name in collection_names:
        collection = db.get_collection(collection_name)
        count = await collection.count_documents({})
        collections[collection_name] = {
            "documents_count": count
        }
        total_documents += count

    # Получаем информацию о шардах и количестве документов в каждом
    shards_info = {}
    replicas_count = {}

    topology_description = client.topology_description
    topology_type = topology_description.topology_type_name
    replicaset_name = topology_description.replica_set_name
    read_preference = client.client_options.read_preference
    shards = {}

    if topology_type == "Sharded":
        try:
            # Получаем список шардов
            shards_list = await client.admin.command("listShards")
            for shard in shards_list.get("shards", {}):
                shards[shard["_id"]] = shard["host"]

            # Для каждого шарда получаем статистику
            for shard_info in shards_list.get("shards", []):
                shard_id = shard_info["_id"]
                shard_host = shard_info["host"]

                # Определяем количество реплик из host строки
                if "/" in shard_host:
                    # Формат: replSetName/host1:port,host2:port,host3:port
                    hosts_part = shard_host.split("/")[1]
                    replica_count = len(hosts_part.split(","))
                else:
                    replica_count = 1

                replicas_count[shard_id] = replica_count

                # Получаем количество документов в шарде
                # Используем collStats для каждой коллекции и суммируем по шардам
                shard_docs = 0
                for collection_name in collection_names:
                    try:
                        # Получаем статистику коллекции
                        stats = await db.command("collStats", collection_name)

                        # Для шардированных коллекций получаем данные по шардам
                        if "shards" in stats and isinstance(stats["shards"], dict):
                            # Проверяем, есть ли данные для этого шарда
                            if shard_id in stats["shards"]:
                                shard_stats = stats["shards"][shard_id]
                                shard_docs += shard_stats.get("count", 0)
                        # Если коллекция не шардирована, collStats не вернет shards
                        # В этом случае все документы в одном шарде (обычно первом)
                        elif "count" in stats and shard_docs == 0:
                            # Если это первый шард и коллекция не шардирована,
                            # все документы в нем
                            if shard_id == shards_list.get("shards", [])[0].get("_id"):
                                shard_docs = stats.get("count", 0)
                    except Exception as e:
                        logger.error(f"Error getting collStats for {collection_name}: {e}")

                # Если не удалось получить через collStats, используем приблизительный метод
                # Только если shard_docs все еще 0
                if shard_docs == 0 and total_documents > 0:
                    num_shards = len(shards_list.get("shards", []))
                    if num_shards > 0:
                        # Равномерное распределение (приблизительное)
                        shard_docs = total_documents // num_shards
                        # Остаток добавляем к первому шарду
                        if shard_id == shards_list.get("shards", [])[0].get("_id"):
                            shard_docs += total_documents % num_shards

                shards_info[shard_id] = {
                    "host": shard_host,
                    "documents_count": shard_docs,
                    "status": "ok"
                }

        except Exception as e:
            logger.error(f"Error getting shards info: {e}")
            # Fallback: используем простой метод
            try:
                shards_list = await client.admin.command("listShards")
                for shard_info in shards_list.get("shards", []):
                    shard_id = shard_info["_id"]
                    shard_host = shard_info["host"]

                    # Определяем количество реплик
                    if "/" in shard_host:
                        hosts_part = shard_host.split("/")[1]
                        replica_count = len(hosts_part.split(","))
                    else:
                        replica_count = 1

                    replicas_count[shard_id] = replica_count

                    # Приблизительное распределение документов
                    num_shards = len(shards_list.get("shards", []))
                    shard_docs = total_documents // num_shards if num_shards > 0 else 0

                    shards_info[shard_id] = {
                        "host": shard_host,
                        "documents_count": shard_docs,
                        "status": "Exception"
                    }
            except Exception as e2:
                logger.error(f"Error in fallback shards info: {e2}")
    cache_enabled = False
    if REDIS_URL:
        cache_enabled = FastAPICache.get_enable()
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
        "shards": shards,
        "shards_info": shards_info,
        "total_documents": total_documents,
        "replicas_count": replicas_count,
        "collections": collections,
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
async def list_users(collection_name: str):
    """
    List all of the user data in the database.
    The response is unpaginated and limited to 1000 results.
    """
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
    """
    Get the record for a specific user, looked up by `name`.
    """

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
    """
    Insert a new user record.

    A unique `id` will be created and provided in the response.
    """
    collection = db.get_collection(collection_name)
    new_user = await collection.insert_one(
        user.model_dump(by_alias=True, exclude=["id"])
    )
    created_user = await collection.find_one({"_id": new_user.inserted_id})
    return created_user
