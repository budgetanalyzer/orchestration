#!/bin/sh

set -eu
umask 077

ACL_FILE="/tmp/users.acl"

cat > "$ACL_FILE" <<EOF
user currency-service reset on >${REDIS_CURRENCY_SERVICE_PASSWORD} ~currency-service:* +get +set +del +scan +ping +auth +hello +info +ttl +pttl +expire +exists +type +object
user redis-ops reset on >${REDIS_CACHE_OPS_PASSWORD} ~* &* +@all
user default reset on >${REDIS_CACHE_DEFAULT_PASSWORD} ~* +ping +auth
EOF

exec redis-server \
  --maxmemory 64mb \
  --maxmemory-policy allkeys-lru \
  --appendonly no \
  --save "" \
  --aclfile "$ACL_FILE" \
  --dir /data \
  --tls-port 6379 \
  --port 0 \
  --tls-cert-file /tls/tls.crt \
  --tls-key-file /tls/tls.key \
  --tls-ca-cert-file /tls-ca/ca.crt \
  --tls-auth-clients no
