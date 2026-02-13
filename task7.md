# Задание 7. Проектирование схем коллекций для шардирования данных

## Примеры коллекций

### Коллекция orders - заказы

```javascript
{
  "_id": ObjectId("77aa..."), // идентификатор заказа
  "user_id": ObjectId("55bb..."), // идентификатор клиента
  "status": "shipped",              // статус
  "created_at": ISODate("2026-02-13T12:00:00Z"),
  "items": [
    {
      "product_id": ObjectId("65cb..."),    // Ссылка для связи на продукт
      "name": "Смартфон yPhone 15",         // Снимок (текстовое описание заказа)
      "price": 89900,                       // Снимок цены на момент оплаты
      "quantity": 1
    },
    {
      "product_id": ObjectId("66fb..."),    // Ссылка для связи на продукт
      "name": "Провод HDMI 1.2 2m",         // Снимок (текстовое описание заказа)
      "price": 300,                         // Снимок цены на момент оплаты
      "quantity": 1
    },    
  ],
  "total_amount": 90200,                    // Снимок суммы
  "delivery": {
    "geosubject": 77,                       // геозона (Субъект РФ)
    "city": "Москва",                       // город
    "address": "ул. Пушкина, д. 5, кв. 1",
    "tracking_number": "TRK123456"
  }
}

```

для шард-ключей можно использовать

- user_id (поиск будет происходить на 1 шарде для текущего пользователя)
- geosubject (если запрос учитывает герзону)
- составной ключ user_id + created_at оптимизирует запросы, касающиеся аналитики
- так же использование идентификатора _id даст лучшее распределение, но и при запросах задействует все шарды

Быстрое списание с созданием заказа можно выполнить так:

```javascript

const session = client.startSession();

try {
  await session.withTransaction(async () => {
    const productId = ObjectId("65cb...");
    const quantityToBuy = 2;
    const zoneCode = "msk";

    // 1. Списываем остаток с проверкой (условие stock >= quantityToBuy)
    const updateResult = await db.collection('products').updateOne(
      { 
        _id: productId, 
        "regional_stock.zone": zoneCode,
        "regional_stock.stock": { $gte: quantityToBuy } // Важно: проверяем наличие!
      },
      { 
        $inc: { 
          "regional_stock.$.stock": -quantityToBuy, 
          "total_stock": -quantityToBuy 
        } 
      },
      { session }
    );

    if (updateResult.modifiedCount === 0) {
      throw new Error("Недостаточно товара на складе или товар не найден");
    }

    // 2. Создаем документ заказа
    await db.collection('orders').insertOne({
      user_id: ObjectId("55bb..."),
      items: [{ product_id: productId, quantity: quantityToBuy, price: 89900 }],
      status: "created",
      created_at: new Date()
    }, { session });

  });
  
  //Заказ успешно оформлен

} catch (error) {
  
  //"Ошибка при оформлении заказа: 

} finally {
  
  await session.endSession();

}
```

Для поиска истории заказа имеет смысл проиндексировать коллекцию, сначала по пользователб, затем по дате создания

```javascript
db.orders.createIndex({ "user_id": 1, "created_at": -1 })
```

получение командой 

```javascript
db.collection('orders')
  .find({ "user_id": userId })
  .sort({ "created_at": -1 }) 
```

Отображение статуса заказа

```javascript
db.collection('orders').findOne(
  { "_id": ObjectId("77aa...") }, // ID заказа
  { projection: { "status": 1, "_id": 0 } } //  только поле status
);
```


### Коллекция products - товары

```javascript
{
  "_id": ObjectId("65cb..."),               // идентификатор 
  "slug": "yphone-15-pro",                  // "безопасное" наименование для индексации
  "name": "Смартфон yPhone 15",             // наименование
  "category": { "id": 101, "name": "Электроника" }, // категория
  "price": 89900,                           // цена
  "currency": "RUB",
  "total_stock": 150,       // Общий остаток для быстрой фильтрации "в наличии"
  "regional_stock": [
    {
      "zone": "msk",       // Код геозоны (Москва)
      "warehouse_id": 1,
      "stock": 100,
    },
    {
      "zone": "bbo",       
      "warehouse_id": 2,
      "stock": 50,
    }
  ]  
  "specs": [ // Массив характеристик 
    { "k": "color", "v": "black" },
    { "k": "ram", "v": "12GB" },
    { "k": "cpu", "v": "A17 Pro" }
  ]
}
```

для шард-ключей можно использовать

- category - поиск будет происходить на 1 шарде *но возможен перегрев по популярной категории)
- составной ключ { category_id: 1, _id: 1 } - частично решит проблему
- так же использование идентификатора _id даст лучшее распределение, но и при запросах задействует все шарды


для эффективного поиска добавим индекс

```javascript
db.products.createIndex({ "category.id": 1, "price": 1 })
```

поиск товара по категории

```javascript
const categoryId = 101;
const minPrice = 50000;
const maxPrice = 100000;

db.collection('products').find({
  "category.id": categoryId,
  "price": { 
    $gte: minPrice, 
    $lte: maxPrice 
  }
})
.sort({ "price": 1 }) // Сортировка от дешевых к дорогим
.limit(20);
```

обновление остатков (но при сильное нагрузке лучше использовать подход записи в кеш Write-Back):

```javascript
db.products.updateOne(
  { _id: productId, "regional_stock.zone": "msk", "regional_stock.stock": { $gte: quantity } },
  { $inc: { 
      "regional_stock.$.stock": -quantity, 
      "total_stock": -quantity 
    } 
  }
)
```

вывод данных о товаре с учетом наличия в геозоне

```javascript
const userZone = "msk";

db.collection('products').findOne(
  { "slug": "superphone-15-pro" },
  {
    projection: {
      name: 1,
      price: 1,
      specs: 1,
      local_stock: {
        $filter: {
          input: "$regional_stock",
          as: "item",
          cond: { $eq: ["$$item.zone", userZone] }
        }
      }
    }
  }
);
```

### Коллекция carts - корзины

```javascript
{
  "_id": ObjectId("88cc..."),
  "user_id": ObjectId("55bb..."), // Ссылка на пользователя (или session_id для анонимов)
  "status": "active",
  "items": [
    {
      "product_id": ObjectId("65cb..."),
      "quantity": 2,
      "added_at": ISODate("2024-02-13T15:30:00Z")
    },
    {
      "product_id": ObjectId("99dd..."),
      "quantity": 1,
      "added_at": ISODate("2024-02-13T15:35:00Z")
    }
  ],
  "created_at": ISODate("2026-02-13T15:35:00Z"),
  "updated_at": ISODate("2026-02-13T15:35:00Z"),
  "expires_at": ISODate("2026-02-20T15:35:00Z") // время для автоудаления старых корзин
}
```

для шард-ключей можно использовать

- user_id (поиск будет происходить на 1 шарде для текущего пользователя)
- так же использование идентификатора _id даст лучшее распределение, но и при запросах задействует все шарды

для ускорения создам индексы

```javascript
db.carts.createIndex({ user_id: 1, status: 1 })
```

создание корзины или добавление товара

```javascript

// искать только активные корзины, для ид пользователя или сессии гостя
const filter =  user_id ? { user_id, status: "active" } : { user_id : session_id, status: "active" }; 

db.collection('carts').updateOne(
  filter, 
  { 
    $setOnInsert: { 
      items: [], 
      created_at: new Date() 
    },
    $set: { updated_at: new Date() }
  },
  { upsert: true } // добавить документ, если его нет
);
```

слияние корзины

```javascript

// Находим анонимную корзину
const guestCart = await db.collection('carts').findOne({ user_id: sessionId });

if (guestCart && guestCart.items.length > 0) {
  
  // Добавляем товары в корзину пользователя
  db.collection('carts').updateOne(
    { user_id: userId, status: "active" },
    { 
      $push: { items: { $each: guestCart.items } }, 
      $set: { updated_at: new Date() }
    },
    { upsert: true }
  );
  
  //  Удаляем старую гостевую корзину
  db.collection('carts').updateOne(
    { _id: guestCart._id },
    { 
      $set: { 
        status: "abandoned", 
        updated_at: new Date() 
      } 
    }
  );
}
```