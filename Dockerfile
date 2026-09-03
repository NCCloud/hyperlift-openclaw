ARG OPENCLAW_VERSION=2026.8.2
FROM ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}
ARG OPENCLAW_VERSION

# OpenClaw 2026.8 dropped Mistral from the image. Bake the official package
# back in (same version as the base) so all six providers work out of the box.
USER root
RUN cd /tmp \
    && tar -xzf "$(npm pack @openclaw/mistral-provider@${OPENCLAW_VERSION} --silent)" \
    && mkdir -p /app/dist/extensions \
    && mv package /app/dist/extensions/mistral \
    && rm -rf openclaw-mistral-provider-*.tgz "$(npm config get cache)" \
    && chown -R node:node /app/dist/extensions/mistral
USER node

# Our plugin, next to the bundled ones: approves browser pairing requests
# (see plugins/device-autopair/index.js).
COPY --chown=node:node plugins/device-autopair/ /app/dist/extensions/device-autopair/

COPY --chown=node:node seed/ /app/seed/
COPY --chown=node:node --chmod=0755 init.sh /app/init.sh

# From `openclaw doctor`: compile cache off the volume, restarts in-process.
ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache \
    OPENCLAW_NO_RESPAWN=1

# Matches gateway.port in the seed config.
EXPOSE 8080

# The base image runs tini as PID 1; init.sh prepares state, then execs the gateway.
ENTRYPOINT ["tini", "-s", "--", "/app/init.sh"]
CMD ["openclaw", "gateway", "run"]
