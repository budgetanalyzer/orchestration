#!/bin/sh

set -eu
umask 077

ACL_FILE="/tmp/users.acl"

cat > "$ACL_FILE" <<EOF
user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~session:* ~oauth2:state:* &* +@all
user ext-authz reset on >${REDIS_EXT_AUTHZ_PASSWORD} ~session:* +hgetall +ping +auth +hello +info
user currency-service reset on >${REDIS_CURRENCY_SERVICE_PASSWORD} ~currency-service:* +get +set +del +keys +scan +ping +auth +hello +info +ttl +pttl +expire +exists +type +object
user redis-ops reset on >${REDIS_OPS_PASSWORD} ~* &* +@all
user default reset on >${REDIS_DEFAULT_PASSWORD} ~* +ping +auth
EOF

exec redis-server \
  --appendonly yes \
  --aclfile "$ACL_FILE" \
  --dir /data \
  --tls-port 6379 \
  --port 0 \
  --tls-cert-file /tls/tls.crt \
  --tls-key-file /tls/tls.key \
  --tls-ca-cert-file /tls-ca/ca.crt \
  --tls-auth-clients no
