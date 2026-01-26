#!/bin/bash
set -e

echo '=== MongoDB Sharding Cluster Initialization ==='

echo ''
echo '1. Waiting for shards to be ready...'

# Проверяем shard1
COUNTER=1
SHARD1_READY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard1:27018 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        echo '✓ shard1:27018 is ready'
        SHARD1_READY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard1:27018 failed to become ready after 30 attempts'
        exit 1
    fi
    echo '  shard1 not ready yet, waiting...'
    sleep 2
    COUNTER=$((COUNTER + 1))
done

# Проверяем shard2
COUNTER=1
SHARD2_READY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard2:27018 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        echo '✓ shard2:27018 is ready'
        SHARD2_READY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard2:27018 failed to become ready after 30 attempts'
        exit 1
    fi
    echo '  shard2 not ready yet, waiting...'
    sleep 2
    COUNTER=$((COUNTER + 1))
done

# Проверяем shard3
COUNTER=1
SHARD3_READY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard3:27018 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        echo '✓ shard3:27018 is ready'
        SHARD3_READY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard3:27018 failed to become ready after 30 attempts'
        exit 1
    fi
    echo '  shard3 not ready yet, waiting...'
    sleep 2
    COUNTER=$((COUNTER + 1))
done

echo ''
echo '2. Initializing shard1 replica set...'
mongosh --host shard1:27018 --eval '
    try {
        rs.initiate({
            _id: "shard1rs",
            members: [
                {_id: 0, host: "shard1:27018", priority: 1}
            ]
        });
        print("✓ Shard1 replica set initialized");
    } catch (e) {
        if (e.codeName === "AlreadyInitialized" || e.message.includes("already initialized")) {
            print("✓ Shard1 already initialized");
        } else {
            throw e;
        }
    }
'

echo 'Waiting for shard1 to become primary...'
COUNTER=1
SHARD1_PRIMARY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard1:27018 --eval "rs.isMaster().ismaster" --quiet 2>/dev/null | grep -q 'true'; then
        echo '✓ shard1 is primary'
        SHARD1_PRIMARY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard1 failed to become primary after 30 attempts'
        exit 1
    fi
    sleep 2
    COUNTER=$((COUNTER + 1))
done

echo ''
echo '3. Initializing shard2 replica set...'
mongosh --host shard2:27018 --eval '
    try {
        rs.initiate({
            _id: "shard2rs",
            members: [
                {_id: 0, host: "shard2:27018", priority: 1}
            ]
        });
        print("✓ Shard2 replica set initialized");
    } catch (e) {
        if (e.codeName === "AlreadyInitialized" || e.message.includes("already initialized")) {
            print("✓ Shard2 already initialized");
        } else {
            throw e;
        }
    }
'

echo 'Waiting for shard2 to become primary...'
COUNTER=1
SHARD2_PRIMARY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard2:27018 --eval "rs.isMaster().ismaster" --quiet 2>/dev/null | grep -q 'true'; then
        echo '✓ shard2 is primary'
        SHARD2_PRIMARY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard2 failed to become primary after 30 attempts'
        exit 1
    fi
    sleep 2
    COUNTER=$((COUNTER + 1))
done

echo ''
echo '4. Initializing shard3 replica set...'
mongosh --host shard3:27018 --eval '
    try {
        rs.initiate({
            _id: "shard3rs",
            members: [
                {_id: 0, host: "shard3:27018", priority: 1}
            ]
        });
        print("✓ Shard3 replica set initialized");
    } catch (e) {
        if (e.codeName === "AlreadyInitialized" || e.message.includes("already initialized")) {
            print("✓ Shard3 already initialized");
        } else {
            throw e;
        }
    }
'

echo 'Waiting for shard3 to become primary...'
COUNTER=1
SHARD3_PRIMARY=false
while [ $COUNTER -le 30 ]; do
    if mongosh --host shard3:27018 --eval "rs.isMaster().ismaster" --quiet 2>/dev/null | grep -q 'true'; then
        echo '✓ shard3 is primary'
        SHARD3_PRIMARY=true
        break
    fi
    if [ $COUNTER -eq 30 ]; then
        echo '✗ shard3 failed to become primary after 30 attempts'
        exit 1
    fi
    sleep 2
    COUNTER=$((COUNTER + 1))
done

echo ''
echo '5. Adding shards to cluster via mongos1...'

# Добавляем shard1
ATTEMPT_COUNTER=1
SHARD1_ADDED=false
while [ $ATTEMPT_COUNTER -le 10 ]; do
    echo "Attempt $ATTEMPT_COUNTER/10 to add shard1..."
    if mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard1rs/shard1:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "success"; then
        echo "✓ shard1 added successfully"
        SHARD1_ADDED=true
        break
    elif mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard1rs/shard1:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "already_exists"; then
        echo "✓ shard1 already exists in cluster"
        SHARD1_ADDED=true
        break
    fi
    
    if [ $ATTEMPT_COUNTER -eq 10 ]; then
        echo "✗ Failed to add shard1 after 10 attempts"
        exit 1
    fi
    
    echo "Retrying in 3 seconds..."
    sleep 3
    ATTEMPT_COUNTER=$((ATTEMPT_COUNTER + 1))
done

# Добавляем shard2
ATTEMPT_COUNTER=1
SHARD2_ADDED=false
while [ $ATTEMPT_COUNTER -le 10 ]; do
    echo "Attempt $ATTEMPT_COUNTER/10 to add shard2..."
    if mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard2rs/shard2:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "success"; then
        echo "✓ shard2 added successfully"
        SHARD2_ADDED=true
        break
    elif mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard2rs/shard2:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "already_exists"; then
        echo "✓ shard2 already exists in cluster"
        SHARD2_ADDED=true
        break
    fi
    
    if [ $ATTEMPT_COUNTER -eq 10 ]; then
        echo "✗ Failed to add shard2 after 10 attempts"
        exit 1
    fi
    
    echo "Retrying in 3 seconds..."
    sleep 3
    ATTEMPT_COUNTER=$((ATTEMPT_COUNTER + 1))
done

# Добавляем shard3
ATTEMPT_COUNTER=1
SHARD3_ADDED=false
while [ $ATTEMPT_COUNTER -le 10 ]; do
    echo "Attempt $ATTEMPT_COUNTER/10 to add shard3..."
    if mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard3rs/shard3:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "success"; then
        echo "✓ shard3 added successfully"
        SHARD3_ADDED=true
        break
    elif mongosh --host mongos1:27017 --eval "
        try {
            const result = sh.addShard('shard3rs/shard3:27018');
            if (result.ok === 1) {
                print('success');
            } else {
                throw new Error(JSON.stringify(result));
            }
        } catch (e) {
            if (e.message.includes('already exists') || e.message.includes('already been added')) {
                print('already_exists');
            } else {
                print('error:' + e.message);
            }
        }
    " --quiet 2>/dev/null | grep -q "already_exists"; then
        echo "✓ shard3 already exists in cluster"
        SHARD3_ADDED=true
        break
    fi
    
    if [ $ATTEMPT_COUNTER -eq 10 ]; then
        echo "✗ Failed to add shard3 after 10 attempts"
        exit 1
    fi
    
    echo "Retrying in 3 seconds..."
    sleep 3
    ATTEMPT_COUNTER=$((ATTEMPT_COUNTER + 1))
done

echo ''
echo '6. Verifying shards were added...'
VERIFY_COUNTER=1
SHARDS_VERIFIED=false
while [ $VERIFY_COUNTER -le 10 ]; do
    SHARD_COUNT=$(mongosh --host mongos1:27017 --eval '
        const configDb = db.getSiblingDB("config");
        print(configDb.shards.countDocuments());
    ' --quiet 2>/dev/null)
    
    if [ "$SHARD_COUNT" = "3" ] 2>/dev/null; then
        echo "✓ All 3 shards are present in cluster"
        SHARDS_VERIFIED=true
        break
    elif [ $VERIFY_COUNTER -eq 10 ]; then
        echo "✗ Only $SHARD_COUNT shards found after 10 attempts (expected 3)"
        exit 1
    fi
    
    echo "Only $SHARD_COUNT shards found, waiting..."
    sleep 3
    VERIFY_COUNTER=$((VERIFY_COUNTER + 1))
done

echo ''
echo '7. Enabling sharding for database "somedb"...'
mongosh --host mongos1:27017 --eval '
    try {
        sh.enableSharding("somedb");
        print("✓ Sharding enabled for database: somedb");
    } catch (e) {
        if (e.message.includes("already enabled")) {
            print("✓ Sharding already enabled for somedb");
        } else {
            throw e;
        }
    }
'

echo ''
echo '8. Refreshing metadata on all mongos routers...'
for ROUTER in mongos1 mongos2 mongos3; do
    if mongosh --host $ROUTER:27017 --eval '
        try {
            const result = db.adminCommand({flushRouterConfig: 1});
            if (result.ok === 1) {
                print("success");
            }
        } catch (e) {
            print("error:" + e.message);
        }
    ' --quiet 2>/dev/null | grep -q "success"; then
        echo "✓ $ROUTER metadata refreshed"
    else
        echo "⚠ $ROUTER metadata refresh failed (continuing anyway)"
    fi
done

echo ''
echo '=== Final Cluster Status ==='
mongosh --host mongos1:27017 --quiet 2>/dev/null --eval '
    print("\nShard Status:");
    try {
        const configDb = db.getSiblingDB("config");
        const shards = configDb.shards.find().toArray();
        print("Shards (" + shards.length + "):");
        shards.forEach(s => {
            print("  •", s._id, "-", s.host);
        });
        
        const databases = configDb.databases.find().toArray();
        print("\nDatabases:");
        databases.forEach(db => {
            print("  •", db._id, "-", (db.partitioned ? "SHARDED" : "NOT SHARDED"));
        });
        
        print("\n✅ MongoDB Sharding Cluster is ready!");
        print("   Shards:", shards.length);
        print("   Database: somedb (sharding enabled)");
    } catch (e) {
        print("⚠ Could not get full cluster status:", e.message);
    }
'

echo ''
echo '✅ Initialization complete! Cluster is ready for use.'
echo ''
echo '🔌 Connection string for applications:'
echo '  mongodb://mongos1:27017,mongos2:27017,mongos3:27017/somedb'