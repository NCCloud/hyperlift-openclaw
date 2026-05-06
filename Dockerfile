FROM ghcr.io/openclaw/openclaw:latest

COPY --chown=node:node seed/ /app/seed/
COPY --chown=node:node --chmod=0755 init.sh /app/init.sh

# Pre-create the state dir with node ownership so a named volume mounted here
# inherits it. Without this, Docker creates the mount point as root on first
# attach, and init.sh (running as node) hits EACCES when writing.
USER root
RUN mkdir -p /home/node/.openclaw && chown node:node /home/node/.openclaw
USER node

ENTRYPOINT ["/app/init.sh"]
CMD ["openclaw", "gateway", "run"]
