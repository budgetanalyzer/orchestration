#!/bin/sh

set -eu
umask 077

ACL_FILE="/tmp/users.acl"

# `default` is off, so no client can authenticate as it, but it keeps full
# permissions on purpose. Redis replays the AOF as `default`, and EXEC re-checks
# ACLs for every command in a replayed MULTI/EXEC block. Session Gateway's
# multi-write Lua scripts are logged that way, so a restricted `default` would
# silently drop their writes on restart (see
# docs/decisions/018-disabled-default-user-for-redis-session-aof-replay.md).
# Probes authenticate as `redis-health`, which may only PING.
cat > "$ACL_FILE" <<EOF
user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~session:* ~user_sessions:* ~oauth2:state:* +hello +auth +client|setinfo +ping +info +hset +hmset +hget +hgetall +expire +del +unlink +sadd +srem +smembers +type +evalsha +eval
user ext-authz reset on >${REDIS_EXT_AUTHZ_PASSWORD} ~session:* +hgetall +ping +auth +hello +info
user redis-ops reset on >${REDIS_SESSION_OPS_PASSWORD} ~* &* +@all
user redis-health reset on >${REDIS_SESSION_HEALTH_PASSWORD} +ping
user default reset off ~* &* +@all
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
