#!/usr/bin/env bash
bash "$(dirname "$0")/initConfigSrv.sh"
bash "$(dirname "$0")/initShard1.sh"
bash "$(dirname "$0")/initShard2.sh"
bash "$(dirname "$0")/initRouter.sh"
bash "$(dirname "$0")/routerCountDocuments.sh"
bash "$(dirname "$0")/shard1CountDocuments.sh"
bash "$(dirname "$0")/shard2CountDocuments.sh"
