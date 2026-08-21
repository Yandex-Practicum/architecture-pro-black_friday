##  Проблема "горячих" шардов

В предыдущем задании я выбрал идентификатор товара в качестве ключа шардирования, поэтому перегруз категории никакне повлиял бы на баланс шардов.

Но даже при такой схеме "горячий" шард все же может появиться:
* если получилось так, что популярные товары оказались на одном шарде
* сам шард слабый по железу и не вывозит нагрузку
* распределение данных еще не было балансировано

### Диагностика

Командой ниже можно получить достаточно объемную информацию по шардированному кластеру, а именно:
* текущий ключ шардирования
* размещение диапазонов
* количество диапазонов на шардах
* состояние балансера
```
sh.status()
```
 

Эта команда позволит проверить само распределение данных по шардам:
* numOwnedDocuments - кол-во документов хранимых в шарде
* ownedSizeBytes - размер всех документов
 ```
sh.getShardedDataDistribution()
 ```

 Ключевые характеристики шардирования (cardinality, frequency, и monotonicity) можно проверить этими командами
 ```
 db.products.configureQueryAnalyzer({
  mode: "full",
  samplesPerSecond: 10
})

db.products.analyzeShardKey(
  {
    _id: "hashed"
  },
  {
    keyCharacteristics: true,
    readWriteDistribution: true,
    sampleSize: 10000
  }
)
 ```

Примерно такой вывод получится:

```
{
  keyCharacteristics: {
    numDocsTotal: Long('1000'),
    numOrphanDocs: Long('0'),
    avgDocSizeBytes: Long('46'),
    numDocsSampled: Long('1000'),
    isUnique: true,
    numDistinctValues: Long('1000'),
    mostCommonValues: [
      {
        value: { _id: ObjectId('6a8371a03905893442151224') },
        frequency: Long('1')
      },
      {
        value: { _id: ObjectId('6a8371a03905893442151229') },
        frequency: Long('1')
      },
      {
        value: { _id: ObjectId('6a8371a0390589344215122b') },
        frequency: Long('1')
      },
      {
        value: { _id: ObjectId('6a8371a03905893442151231') },
        frequency: Long('1')
      },
      {
        value: { _id: ObjectId('6a8371a03905893442151232') },
        frequency: Long('1')
      }
    ],
    monotonicity: { recordIdCorrelationCoefficient: 0, type: 'not monotonic' },
    note: 'Due to performance reasons, the analyzeShardKey command does not filter out orphan documents when calculating metrics about the characteristics of the shard key. Therefore, if "numOrphanDocs" is large relative to "numDocsTotal", you may want to rerun the command at some other time to get more accurate "numDistinctValues" and "mostCommonValues" metrics.'
  },
  readDistribution: {
    sampleSize: {
      total: Long('0'),
      find: Long('0'),
      aggregate: Long('0'),
      count: Long('0'),
      distinct: Long('0')
    }
  },
  writeDistribution: {
    sampleSize: {
      total: Long('0'),
      update: Long('0'),
      delete: Long('0'),
      findAndModify: Long('0')
    }
  },
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1786999400, i: 2 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1786999400, i: 2 })
}
```

 * numDistinctValues - общее кол-во уникальных значений. Чем оно больше - тем выше кардинальность
 * mostCommonValues - показывает наиболее часто встречающиеся значения, что предупреждает о потенциальных проблемах маршрутизации
 * monotonicity.type - monotonic/not monotonic. Монотонные ключи пишутся подряд на один шард, что тоже может вызвать проблемы

 ### Полезные команды

 Если данные нормально распределены, но какой-то один диапазон стал горячим - можно воспользоваться командой `moveRange` которая перемещает определенный диапазон в другой шард

 ```
db.adminCommand({
  moveRange: "mobile_world.products",
  toShard: "shard-2",
  min: {
    _id: NumberLong("<нижняя граница хеша>")
  },
  max: {
    _id: NumberLong("<верхняя граница хеша>")
  }
})
 ```

 Если данные плохо распределены или мощностей не хватает, то можно, к примеру, добавить еще один шард и вызывать ребалансировку командой `reshardCollection`

 ```
 db.adminCommand({
  reshardCollection: "mobile_world.products",
  key: {
    _id: "hashed"
  },
  forceRedistribution: true
})
 ```


Автоматическим распределением занимается балансер. Он контролирует объём данных коллекции на каждом шарде и автоматически мигрирует диапазоны хешированного `_id` с более заполненных шардов на менее заполненные. После добавления нового шарда балансер также автоматически начнёт переносить на него данные.

Включить его можно командой `sh.startBalancer()`. Также нужно разрешить балансировку и миграции:
```
sh.enableBalancing(
  "mobile_world.products"
)

sh.enableMigrations(
  "mobile_world.products"
)
```

После этого можно проверить его командой:
```
sh.balancerCollectionStatus("mobile_world.products")

В выводе будет что-то типа
{
  chunkSize: 128,
  balancerCompliant: true,
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1787000431, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1787000431, i: 1 })
}
```

* balancerCompliant - значит данные сбалансированы
