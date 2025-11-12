// --- 1. Создание заказа (с одновременным списанием остатков) ---
// Предполагается, что списание остатков происходит в отдельной операции с коллекцией `products`
db.orders.insertOne({
  "_id": "order_002",
  "user_id": "user_456",
  "created_at": "2025-04-05T14:30:00Z",
  "items": [
    {
      "product_id": "prod_002",
      "quantity": 1,
      "price": 18990
    }
  ],
  "status": "pending",
  "total_amount": 18990,
  "geo_zone": "Екатеринбург"
});

// --- 2. Поиск истории заказов конкретного пользователя ---
db.orders.find(
  { "user_id": "user_123" },
  {
    projection: {
      "_id": 1,
      "created_at": 1,
      "status": 1,
      "total_amount": 1,
      "items": 1
    }
  }
).sort({ "created_at": -1 });

// --- 3. Отображение текущего статуса заказа ---
db.orders.findOne(
  { "_id": "order_001" },
  { projection: { "status": 1, "updated_at": 1 } }
);
