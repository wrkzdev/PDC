#!/bin/sh
# Render the nginx config from the environment, then hand over to nginx.
set -eu
: "${PDCD_UPSTREAM:=pdcd:19211}"
: "${CORS_ALLOW_ORIGIN:=*}"
: "${RATE_LIGHT:=20}"
: "${RATE_HEAVY:=5}"
: "${ACCESS_LOG:=off}"
if [ "${ACCESS_LOG}" = "off" ]; then
  ACCESS_LOG_DIRECTIVE="access_log off;"
else
  ACCESS_LOG_DIRECTIVE="access_log /dev/${ACCESS_LOG} pdc_minimal;"
fi
export PDCD_UPSTREAM CORS_ALLOW_ORIGIN RATE_LIGHT RATE_HEAVY ACCESS_LOG_DIRECTIVE
envsubst '${PDCD_UPSTREAM} ${CORS_ALLOW_ORIGIN} ${RATE_LIGHT} ${RATE_HEAVY} ${ACCESS_LOG_DIRECTIVE}' \
  < /etc/nginx/pdc/nginx.conf.template > /tmp/pdc-nginx.conf
nginx -t -c /tmp/pdc-nginx.conf
exec "$@"
