#!/bin/sh
# Render the nginx config from the environment, then hand over to nginx.
set -eu
: "${PDCD_UPSTREAM:=pdcd:19211}"
: "${CORS_ALLOW_ORIGIN:=*}"
: "${RATE_LIGHT:=20}"
: "${RATE_HEAVY:=5}"
export PDCD_UPSTREAM CORS_ALLOW_ORIGIN RATE_LIGHT RATE_HEAVY
envsubst '${PDCD_UPSTREAM} ${CORS_ALLOW_ORIGIN} ${RATE_LIGHT} ${RATE_HEAVY}' \
  < /etc/nginx/pdc/nginx.conf.template > /tmp/pdc-nginx.conf
nginx -t -c /tmp/pdc-nginx.conf
exec "$@"
