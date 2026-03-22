#!/bin/sh

set -eu

ACL_FILE="/tmp/users.acl"

cat > "$ACL_FILE" <<EOF
user session-gateway reset on >${REDIS_SESSION_GATEWAY_PASSWORD} ~spring:session:* ~extauthz:session:* &* +@all
user ext-authz reset on >${REDIS_EXT_AUTHZ_PASSWORD} ~extauthz:session:* +hgetall +ping +auth +hello +info
user currency-service reset on >${REDIS_CURRENCY_SERVICE_PASSWORD} ~currency-service:* +get +set +del +keys +scan +ping +auth +hello +info +ttl +pttl +expire +exists +type +object
user redis-ops reset on >${REDIS_OPS_PASSWORD} ~* &* +@all
user default reset on >${REDIS_DEFAULT_PASSWORD} ~* +ping +auth
EOF

exec redis-server --appendonly yes --aclfile "$ACL_FILE"
