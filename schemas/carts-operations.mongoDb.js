// --- 1. Создание новой корзины для авторизованного пользователя ---
db.carts.insertOne({
  "_id": "cart_user_123",
  "user_id": "user_123",
  "session_id": null,
  "items": [
    {
      "product_id": "prod_001",
      "quantity": 2
    },
    {
      "product_id": "prod_005",
      "quantity": 1
    }
  ],
  "status": "active",
  "created_at": ISODate("2025-04-05T10:00:00Z"),
  "updated_at": ISODate("2025-04-05T10:00:00Z"),
  "expires_at": ISODate("2025-04-12T10:00:00Z") // TTL: 7 дней
});

// --- 2. Создание гостевой корзины (по session_id) ---
db.carts.insertOne({
  "_id": "cart_sess_xyz987",
  "user_id": null,
  "session_id": "session_xyz987",
  "items": [
    {
      "product_id": "prod_002",
      "quantity": 1
    }
  ],
  "status": "active",
  "created_at": ISODate("2025-04-05T14:30:00Z"),
  "updated_at": ISODate("2025-04-05T14:30:00Z"),
  "expires_at": ISODate("2025-04-06T14:30:00Z") // TTL: 24 часа
});

// --- 3. Получение корзины по user_id ---
db.carts.findOne(
  { "user_id": "user_123", "status": "active" },
  {
    projection: {
      "items": 1,
      "updated_at": 1,
      "status": 1
    }
  }
);

// --- 4. Получение корзины по session_id (для гостя) ---
db.carts.findOne(
  { "session_id": "session_xyz987", "status": "active" }
);

// --- 5. Обновление количества товара в корзине ---
db.carts.updateOne(
  { "user_id": "user_123", "items.product_id": "prod_001" },
  {
    $set: { "items.$.quantity": 3 },
    $currentDate: { "updated_at": true }
  }
);

// --- 6. Добавление нового товара в корзину ---
db.carts.updateOne(
  { "user_id": "user_123" },
  {
    $push: { "items": { "product_id": "prod_003", "quantity": 1 } },
    $currentDate: { "updated_at": true }
  }
);

// --- 7. Удаление товара из корзины ---
db.carts.updateOne(
  { "user_id": "user_123" },
  {
    $pull: { "items": { "product_id": "prod_005" } },
    $currentDate: { "updated_at": true }
  }
);

// --- 8. Очистка корзины после оформления заказа (смена статуса) ---
db.carts.updateOne(
  { "_id": "cart_user_123" },
  {
    $set: { "status": "ordered" },
    $currentDate: { "updated_at": true }
  }
);
