FROM ghcr.io/openclaw/openclaw:2026.6.1

COPY --chown=node:node seed/ /app/seed/
COPY --chown=node:node --chmod=0755 init.sh /app/init.sh

# matches gateway.port in seed/openclaw.default.json.
EXPOSE 8080

# The base image already runs under tini as PID 1; we just point its entrypoint
# at init.sh, which prepares the state dir / git sync and then execs the gateway.
ENTRYPOINT ["tini", "-s", "--", "/app/init.sh"]
CMD ["openclaw", "gateway", "run"]
