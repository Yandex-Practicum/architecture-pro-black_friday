# Architectural Report: MongoDB & Cassandra — Tasks 7–10

## Table of Contents
1. Introduction  
2. Task 7 — MongoDB Data Modeling & Sharding Keys  
   - 2.1 Collection Schemas  
   - 2.2 Shard Key Choices  
   - 2.3 Example MongoDB Sharding Commands  
   - 2.4 ASCII Diagrams  
3. Task 8 — Hot Shard Detection & Mitigation  
   - 3.1 Metrics  
   - 3.2 Diagnostic Queries  
   - 3.3 Balancing & Resharding Strategies  
   - 3.4 ASCII Diagrams  
4. Task 9 — Read Preferences & Consistency  
   - 4.1 Primary vs Secondary Read Matrix  
   - 4.2 Acceptable Lag  
   - 4.3 Example Configurations  
5. Task 10 — Cassandra Migration Architecture  
   - 5.1 What to Migrate & Why  
   - 5.2 Cassandra Data Models  
   - 5.3 Partition Keys & Hot Partition Prevention  
   - 5.4 Consistency & Repair Strategies  
   - 5.5 ASCII Diagrams  
6. Summary  

---

# 1. Introduction

This architectural document consolidates tasks **7–10**, covering:

- MongoDB collection modeling  
- Sharding strategy  
- Hot shard detection and mitigation  
- Read preference consistency rules  
- Migration of high‑load entities to Cassandra  

The document uses ASCII diagrams for clarity and contains full rationale, examples, metrical recommendations, and schema definitions.

---

# 2. Task 7 — MongoDB Data Modeling & Sharding Keys

## 2.1 Collection Schemas

### **Collection: products**

```
{
  "_id": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "stock": {
    "<geo_zone>": Number
  },
  "attributes": {
    "color": String,
    "size": String
  }
}
```

### **Collection: orders**

```
{
  "_id": UUID,
  "user_id": UUID,
  "created_at": Date,
  "items": [
    { "product_id": UUID, "price": Number, "qty": Number }
  ],
  "status": "new" | "paid" | "shipped" | "delivered",
  "total": Number,
  "geo_zone": String
}
```

### **Collection: carts**

```
{
  "_id": UUID,
  "user_id": UUID,
  "session_id": String,
  "items": [
    { "product_id": UUID, "quantity": Number }
  ],
  "status": "active" | "ordered" | "abandoned",
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date
}
```

---

## 2.2 Shard Key Choices

### **products**

**Shard key:**
```
{ category: 1, _id: "hashed" }
```

**Rationale:**

- category distributes queries by filtering usage  
- _id hashed ensures even distribution inside each category  
- prevents hotspots from popular categories (e.g., “electronics”)

---

### **orders**

**Shard key:**
```
{ user_id: 1, created_at: 1 }
```

**Pros:**

- users scan their own orders  
- prevents enormous partitions by adding time component  

---

### **carts**

**Derived key `owner_key`:**

```
owner_key = "user:<id>" OR "session:<id>"
```

**Shard key:**
```
{ owner_key: "hashed" }
```

**Rationale:**

- massive cardinality, perfect distribution  
- each cart fits a single partition  

---

## 2.3 Example MongoDB Sharding Commands

### Products

```
sh.shardCollection("shop.products", { category: 1, _id: "hashed" });
```

### Orders

```
sh.shardCollection("shop.orders", { user_id: 1, created_at: 1 });
```

### Carts

```
sh.shardCollection("shop.carts", { owner_key: "hashed" });
```

---

## 2.4 ASCII Diagram — MongoDB Cluster (Sharded)

```
                   +----------------+
                   |   mongos       |
                   +--------+-------+
                            |
                 -------------------------
                 |                       |
        +--------v--------+     +--------v--------+
        |   Shard 1       |     |    Shard 2      |
        |  (RS: 1-1,1-2)  |     |  (RS: 2-1,2-2)   |
        +--------+--------+     +--------+--------+
                 |                       |
                 -------------------------
                            |
                    +-------v-------+
                    | Config Server |
                    +---------------+
```

---

# 3. Task 8 — Hot Shard Detection & Mitigation

## 3.1 Metrics to Monitor

| Metric | Purpose |
|--------|---------|
| CPU per shard | Detect overloaded nodes |
| Disk IOPS | Identify I/O hotspots |
| Network throughput | Identify skewed traffic |
| Chunk count per shard | Detect uneven data distribution |
| Collection size per shard | Direct indicator of imbalance |
| Query latency distribution | Detect slow shards |
| Ops/sec by operation type | Understand load profile |

---

## 3.2 Diagnostic Commands

### Check chunk distribution:

```
use config
db.chunks.aggregate([
  { $match: { ns: "shop.products" }},
  { $group: { _id: "$shard", cnt: { $sum: 1 }}}
])
```

### Storage statistics:

```
db.products.aggregate([{ $collStats: { storageStats: {} } }])
```

---

## 3.3 Mitigation Strategies

### **1. Resharding**

```
db.adminCommand({
  reshardCollection: "shop.products",
  key: { category: 1, _id: "hashed" }
});
```

### **2. Manual split**

```
sh.splitAt("shop.products",
  { category: "electronics", price: 500 }
)
```

### **3. Move chunks**

```
sh.moveChunk("shop.products",
    { category: "electronics", price: 500 },
    "shard02"
)
```

### **4. Zonal sharding**

Useful if categories intentionally grouped.

---

## 3.4 ASCII Diagram — Hot Shard Scenario

```
          +-----------+
          |  Shard 1  |  <--- HOT (70% of "electronics")
          +-----------+
                ^
                |
   uneven distribution due to range-based shard key
                |
          +-----------+
          |  Shard 2  |
          +-----------+
```

After resharding (hashed sub‑key):

```
   electronics items --> evenly distributed across all shards
```

---

# 4. Task 9 — Read Preferences & Consistency

## 4.1 Primary vs Secondary Read Matrix

| Collection | Operation | Read Target | Reason |
|------------|-----------|-------------|--------|
| products | catalog browsing | **secondary** | eventual OK |
| products | add to cart | primaryPreferred | verify price/stock |
| products | final checkout | **primary** | strict consistency |
| orders | history | secondaryPreferred | stale OK |
| orders | payment | **primary** | critical data |
| carts | read current | **primary** | must be fresh |
| carts | TTL cleanup | secondary | not user-facing |

---

## 4.2 Acceptable Replication Lag

| Operation | Lag |
|----------|------|
| catalog browsing | 3–10s |
| order history | 3–5s |
| stock pre-check | 1–2s |
| checkout & payments | 0s |
| carts operations | 0s |

---

## 4.3 Minimal Example Configuration (Python)

```
MongoClient(
    uri,
    readPreference="secondaryPreferred"
)
```

For strict ops:

```
MongoClient(
    uri,
    readPreference="primary"
)
```

---

# 5. Task 10 — Cassandra Migration Architecture

## 5.1 What to Migrate & Why

| Entity | Migrate? | Reason |
|--------|----------|--------|
| cart data | YES | high write load, TTL, low consistency need |
| sessions | YES | massive throughput |
| order history | YES | append-only, high volume |
| product stock | YES (optional) | frequent writes |
| payments | NO | requires strict consistency |

---

# 5.2 Cassandra Data Models

## orders_by_user

```
CREATE TABLE orders_by_user (
    user_id uuid,
    year_month text,
    order_ts timeuuid,
    order_id uuid,
    status text,
    total decimal,
    PRIMARY KEY ((user_id, year_month), order_ts)
) WITH CLUSTERING ORDER BY (order_ts DESC);
```

---

## carts

```
CREATE TABLE carts (
    owner_key text,
    cart_id uuid,
    status text,
    items map<uuid, int>,
    updated_at timestamp,
    PRIMARY KEY(owner_key)
);
```

---

## sessions

```
CREATE TABLE sessions (
    session_id uuid,
    user_id uuid,
    created_at timestamp,
    last_seen timestamp,
    PRIMARY KEY(session_id)
) WITH default_time_to_live=86400;
```

---

## product_stock_by_geo

```
CREATE TABLE product_stock_by_geo (
    product_id uuid,
    geo_zone text,
    stock int,
    updated_at timestamp,
    PRIMARY KEY((product_id, geo_zone))
);
```

---

# 5.3 Partition Key Rationale

- Always choose **high cardinality** field  
- Avoid “hot partitions” like category only  
- Add bucketing where needed: `(user_id, year_month)`  
- Keep partitions small and uniform  

---

# 5.4 Consistency & Repair Strategy

| Entity | Write CL | Read CL | Repair |
|--------|----------|---------|--------|
| carts | LOCAL_ONE | LOCAL_ONE | rare |
| sessions | LOCAL_ONE | LOCAL_ONE | rare |
| orders | LOCAL_QUORUM | LOCAL_QUORUM | regular |
| product_stock | depends on SLA | depends | periodic |

Enable Hinted Handoff for all.

---

# 5.5 ASCII Diagram — Cassandra Ring

```
                 +-----------+
                 |  Node A   |
                 +-----------+
                      |
              -----------------
              |               |
        +-----------+   +-----------+
        |  Node B   |   |  Node C   |
        +-----------+   +-----------+

Data partitioned by consistent hashing across all nodes
```

---

# 6. Summary

This unified architectural report covers:

- MongoDB schema & sharding design  
- Hot shard detection and stabilization  
- Read preference policy  
- Cassandra migration strategy  
- Data models optimized for horizontal scaling  

The solution ensures high availability, performance, and resilience under peak load conditions.

