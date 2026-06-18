FROM ghcr.io/openclaw/openclaw:2026.6.8

COPY --chown=node:node seed/ /app/seed/
COPY --chown=node:node --chmod=0755 init.sh /app/init.sh

# Startup tuning per `openclaw doctor`: ephemeral compile cache (deliberately off
# the persistent volume), and in-process restarts — no supervisor in a container.
ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache \
    OPENCLAW_NO_RESPAWN=1

# matches gateway.port in seed/openclaw.default.json.
EXPOSE 8080

# The base image already runs under tini as PID 1; we just point its entrypoint
# at init.sh, which prepares the state dir / git sync and then execs the gateway.
ENTRYPOINT ["tini", "-s", "--", "/app/init.sh"]
CMD ["openclaw", "gateway", "run"]
