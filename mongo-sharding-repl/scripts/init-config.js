while (true) {
  try {
    rs.initiate(
      {
        _id: "config_server", 
        configsvr: true, 
        members: [{
            _id: 0, 
            host: "config1:27017"
          }, { 
            _id: 1, 
            host: "config2:27017"
          }, { 
            _id: 2, 
            host: "config3:27017" 
          }]
      });
    break;
  } catch (e) {
    print("Waiting for other config servers to start...");
    sleep(5000);
  }
}