#!/bin/bash
set -euo pipefail

docker exec paperless-webserver-1 document_exporter ../export -d
# 1000:1000 owns ~/vikunja/backups; as postgres the write is denied
docker exec -u 1000:1000 vikunja-db /usr/local/bin/pg-dump.sh
docker exec borgmatic borgmatic create --stats
