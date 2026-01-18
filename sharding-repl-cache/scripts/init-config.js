const configServers = ["config1:27017", "config2:27017", "config3:27017"];
let attempts = 0;
const maxAttempts = 10;

while (attempts < maxAttempts) {
  try {
    const conn = new Mongo(configServers[0]);
    const admin = conn.getDB("admin");
    
    // Проверяем статус репликасета
    try {
      const status = admin.runCommand({replSetGetStatus: 1});
      print("Config server replica set already initialized:", status);
      break;
    } catch (e) {
      if (e.codeName === "NotYetInitialized") {
        // Инициализируем config сервер
        const config = {
          _id: "config_server",
          configsvr: true,
          members: [
            { _id: 0, host: "config1:27017" },
            { _id: 1, host: "config2:27017" },
            { _id: 2, host: "config3:27017" }
          ]
        };
        
        const result = admin.runCommand({replSetInitiate: config});
        print("Replica set initialization result:", result);
        
        // Ждем завершения инициализации
        sleep(10000);
        break;
      }
    }
  } catch (e) {
    print(`Attempt ${attempts + 1} failed: ${e}`);
    sleep(5000);
    attempts++;
  }
}

if (attempts >= maxAttempts) {
  print("Failed to initialize config server replica set after maximum attempts");
  quit(1);
}