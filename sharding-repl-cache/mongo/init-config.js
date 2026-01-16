
    rs.initiate({
      _id: "configserver", 
      configsvr: true, 
      version: 1, 
      members: [ 
        { _id: 0, host : "config_srv_1:27017" }, 
        { _id: 1, host : "config_srv_2:27017" }, 
        { _id: 2, host : "config_srv_3:27017" }
      ] 
    });




