// --- 1. Обновление остатков товара при покупке (в транзакции с заказом) ---
db.products.updateOne(
  { "product_id": "prod_002", "category": "Электроника" },
  { $inc: { "inventory.Екатеринбург": -1 } }
);

// --- 2. Поиск товаров по категории ---
db.products.find(
  { "category": "Электроника" },
  {
    projection: {
      "name": 1,
      "price": 1,
      "inventory.Екатеринбург": 1,
      "attributes": 1
    }
  }
).limit(20);

// --- 3. Фильтрация товаров по диапазону цен внутри категории ---
db.products.find(
  {
    "category": "Электроника",
    "price": { $gte: 10000, $lte: 30000 }
  },
  { projection: { "name": 1, "price": 1, "inventory": 1 } }
).sort({ "price": 1 });

// --- 4. Получение полного описания товара по ID ---
db.products.findOne({ "product_id": "prod_005" });
