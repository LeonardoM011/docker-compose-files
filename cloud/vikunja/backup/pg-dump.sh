#!/bin/sh
set -eu

KEEP=7
OUT="/backups/vikunja-$(date +%Y%m%d-%H%M).sql.gz"

pg_dump -U vikunja --clean --if-exists vikunja | gzip -9 > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"

ls -1t /backups/vikunja-*.sql.gz | tail -n +$((KEEP + 1)) | xargs -r rm -f
