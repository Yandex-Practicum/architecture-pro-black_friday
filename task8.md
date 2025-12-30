# Задание 8. Выявление и устранение «горячих» шардов
### Метрики
Мониторим:
- Query Volume per Shard
- Chunk Count
- Latency
- CPU/IO
- Balancer status

## Автоматические механизмы перераспределения
- Hashed или Compound шард-ключ
- Auto-splitting
- Balancer миграции чанков
- Кэширование популярных запросов