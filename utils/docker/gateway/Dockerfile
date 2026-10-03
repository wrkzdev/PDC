# Public-node gateway: allowlist + CORS + rate limits in front of pdcd RPC (TLS is added by the Caddy service).
FROM nginxinc/nginx-unprivileged:1.27-alpine
USER root
RUN mkdir -p /etc/nginx/pdc && chown nginx:nginx /etc/nginx/pdc
COPY --chown=nginx:nginx gateway.js nginx.conf.template /etc/nginx/pdc/
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/pdc-gateway-entrypoint.sh
USER nginx
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/pdc-gateway-entrypoint.sh"]
CMD ["nginx", "-c", "/tmp/pdc-nginx.conf", "-g", "daemon off;"]
