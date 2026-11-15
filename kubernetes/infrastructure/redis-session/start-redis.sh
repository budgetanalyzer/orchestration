#!/bin/sh

set -eu
umask 077

ACL_FILE="/tmp/users.acl"

cat > "$ACL_FILE" <<EOF
user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~session:* ~user_sessions:* ~oauth2:state:* +hello +auth +client|setinfo +ping +info +hset +hmset +hget +hgetall +expire +del +unlink +sadd +srem +smembers +type +evalsha +eval
user ext-authz reset on >${REDIS_EXT_AUTHZ_PASSWORD} ~session:* +hgetall +ping +auth +hello +info
user redis-ops reset on >${REDIS_SESSION_OPS_PASSWORD} ~* &* +@all
user default reset on >${REDIS_SESSION_DEFAULT_PASSWORD} ~* +ping +auth
EOF

exec redis-server \
  --appendonly yes \
  --maxmemory 128mb \
  --maxmemory-policy noeviction \
  --aclfile "$ACL_FILE" \
  --dir /data \
  --tls-port 6379 \
  --port 0 \
  --tls-cert-file /tls/tls.crt \
  --tls-key-file /tls/tls.key \
  --tls-ca-cert-file /tls-ca/ca.crt \
  --tls-auth-clients no
