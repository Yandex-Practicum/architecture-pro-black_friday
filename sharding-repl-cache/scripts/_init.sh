#!/usr/bin/env bash
bash "$(dirname "$0")/initConfigSrv.sh"
bash "$(dirname "$0")/initRS1.sh"
bash "$(dirname "$0")/initRS2.sh"
bash "$(dirname "$0")/initRouter.sh"
bash "$(dirname "$0")/routerCountDocuments.sh"
bash "$(dirname "$0")/shard1_1CountDocuments.sh"
bash "$(dirname "$0")/shard2_1CountDocuments.sh"
