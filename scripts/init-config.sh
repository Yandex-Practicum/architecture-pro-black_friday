#!/bin/bash
set -e

echo '=== Initializing Config Servers Replica Set ==='

echo ''
echo '1. Waiting for all config servers to be ready...'

# Ждем готовности config серверов
counter=1
while [ $counter -le 60 ]; do
    ready=0
    
    if mongosh --host configsvr1:27019 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        ready=$((ready + 1))
    fi
    
    if mongosh --host configsvr2:27019 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        ready=$((ready + 1))
    fi
    
    if mongosh --host configsvr3:27019 --eval "db.adminCommand('ping').ok" --quiet 2>/dev/null | grep -q '1'; then
        ready=$((ready + 1))
    fi
    
    if [ $ready -eq 3 ]; then
        echo '✓ All 3 config servers are ready!'
        break
    fi
    
    if [ $counter -eq 60 ]; then
        echo "✗ Only $ready/3 config servers ready after 60 attempts"
        exit 1
    fi
    
    echo "  Ready: $ready/3, waiting... (attempt $counter/60)"
    sleep 2
    counter=$((counter + 1))
done

echo ''
echo '2. Initializing config replica set...'

attempt=1
while [ $attempt -le 15 ]; do
    echo "Attempt $attempt/15 to initialize config replica set..."
    
    result=$(mongosh --host configsvr1:27019 --eval '
        try {
            const config = {
                _id: "configrs",
                configsvr: true,
                members: [
                    {_id: 0, host: "configsvr1:27019", priority: 1}
                ]
            };
            
            const res = rs.initiate(config);
            if (res.ok === 1) {
                print("INIT_SUCCESS");
            } else {
                print("INIT_FAILED:" + JSON.stringify(res));
            }
        } catch (e) {
            if (e.codeName === "AlreadyInitialized" || e.message.includes("already initialized")) {
                print("ALREADY_INITIALIZED");
            } else {
                print("ERROR:" + e.message);
            }
        }
    ' --quiet 2>/dev/null || true)
    
    if echo "$result" | grep -q "INIT_SUCCESS"; then
        echo "✓ Config replica set initialized successfully"
        break
    elif echo "$result" | grep -q "ALREADY_INITIALIZED"; then
        echo "✓ Config replica set already initialized"
        break
    elif [ $attempt -eq 15 ]; then
        echo "✗ Failed to initialize config replica set after 15 attempts"
        echo "Last result: $result"
        exit 1
    fi
    
    echo "Retrying in 3 seconds..."
    sleep 3
    attempt=$((attempt + 1))
done

echo ''
echo '3. Waiting for replica set to elect primary...'

i=1
PRIMARY_FOUND=false
while [ $i -le 60 ]; do
    
        if mongosh --host configsvr1:27019 --eval "rs.isMaster().ismaster" --quiet 2>/dev/null | grep -q 'true'; then
            echo "✓ Found primary on configsvr1"
            PRIMARY_FOUND=true
            break
        fi
    
    
    if [ $i -eq 60 ]; then
        echo "✗ Config replica set failed to elect primary after 60 attempts"
        echo -e "\nReplica set status:"
        mongosh --host configsvr1:27019 --eval "rs.status()" --quiet 2>/dev/null || true
        exit 1
    fi
    
    echo "  Waiting for primary election... (attempt $i/60)"
    sleep 5
    i=$((i + 1))
done

echo ''
echo '3-1. Adding replicas...'
mongosh --host configsvr1:27019 --eval "
    try { rs.add('configsvr2:27019') } catch(e) {}
    try { rs.add('configsvr3:27019') } catch(e) {}
    print('✓ Replicas added');
" --quiet 2>/dev/null || true
sleep 10

echo ''
echo '4. Verifying replica set is healthy...'

i=1
while [ $i -le 30 ]; do
    if mongosh --host configsvr3:27019 --eval "rs.status().ok" --quiet 2>/dev/null | grep -q '1'; then
        echo "✓ Replica set is healthy"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "✗ Replica set not healthy after 30 attempts"
        exit 1
    fi
    
    sleep 2
    i=$((i + 1))
done

echo ''
echo '5. Verifying all members are in replica set...'

i=1
while [ $i -le 30 ]; do
    MEMBER_COUNT=$(mongosh --host configsvr1:27019 --eval "rs.status().members.length" --quiet 2>/dev/null)
    
    if [ "$MEMBER_COUNT" = "3" ] 2>/dev/null; then
        echo "✓ All 3 members are in replica set"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "✗ Only $MEMBER_COUNT/3 members in replica set after 30 attempts"
        exit 1
    fi
    
    echo "  Members: $MEMBER_COUNT/3, waiting..."
    sleep 3
    i=$((i + 1))
done

echo ''
echo '✅ Config initialization completed successfully!'
echo '   Config servers are ready for mongos connections.'
echo '   Connection string: configrs/configsvr1:27019,configsvr2:27019,configsvr3:27019'