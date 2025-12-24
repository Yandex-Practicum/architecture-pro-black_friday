# MongoDB Sharding (PoC)

Проект демонстрирует базовую настройку **шардирования MongoDB** для PoC/учебного кейса:
- 1 Config Server
- 2 шарда
- 1 `mongos` router
- API, работающее через `mongos`

Шардирование инициализируется **автоматически при первом запуске** с помощью init-скрипта.

---

## 📦 Состав системы

- **configSrv** — Config Server (mongod)
- **shard1**, **shard2** — шарды MongoDB
- **mongos** — роутер
- **mongo-init** — one-shot контейнер для инициализации шардинга
- **pymongo_api** — приложение, подключающееся к MongoDB через `mongos`

---

## 🚀 Запуск проекта

### 1. Поднимает docker
```bash
docker compose up -d
```
### 2. Запускаем скрипт инициации `mongo` и за пополнения данными
```bash
./scripts/mongo-init.sh
```
