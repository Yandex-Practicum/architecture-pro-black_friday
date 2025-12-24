// mongosh
use shop;

db.products.deleteMany({});

const categories = [
  { name: "Электроника", weight: 70 },
  { name: "Одежда", weight: 10 },
  { name: "Обувь", weight: 6 },
  { name: "Дом", weight: 6 },
  { name: "Спорт", weight: 4 },
  { name: "Детям", weight: 4 },
];

const geoZones = ["RU-MOW", "RU-SPE", "RU-KDA", "RU-NVS", "EU-ROM"];
const colors = ["black", "white", "blue", "red", "green", "silver"];
const memories = ["64GB", "128GB", "256GB", "512GB", "1TB"];

function pickWeighted(items) {
  const total = items.reduce((s, x) => s + x.weight, 0);
  let r = Math.random() * total;
  for (const x of items) {
    r -= x.weight;
    if (r <= 0) return x.name;
  }
  return items[items.length - 1].name;
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick(arr) {
  return arr[randInt(0, arr.length - 1)];
}

function makeStocks() {
  const count = randInt(1, 3);
  const used = new Set();
  const stocks = [];
  while (stocks.length < count) {
    const z = pick(geoZones);
    if (used.has(z)) continue;
    used.add(z);
    stocks.push({ geo_zone: z, qty: randInt(0, 500) });
  }
  return stocks;
}

const now = new Date();
const docs = [];

for (let i = 1; i <= 10000; i++) {
  const category = pickWeighted(categories);
  const createdAt = new Date(now.getTime() - randInt(0, 60) * 24 * 60 * 60 * 1000);
  const updatedAt = new Date(createdAt.getTime() + randInt(0, 10) * 60 * 60 * 1000);

  docs.push({
    _id: ObjectId().valueOf(), // строка
    category,
    price: randInt(500, 200000),
    name: `${category} товар #${i}`,
    created_at: createdAt,
    updated_at: updatedAt,
    stocks: makeStocks(),
    attrs: {
      color: pick(colors),
      memory: category === "Электроника" ? pick(memories) : null,
    },
  });
}

db.products.insertMany(docs);
db.products.countDocuments();
