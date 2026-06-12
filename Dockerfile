FROM docker.io/cloudflare/sandbox:0.7.0

# Install Node.js 22 (required by OpenClaw) and rclone (for R2 persistence)
# The base image has Node 20, we need to replace it with Node 22
# Using direct binary download for reliability
# OpenClaw 2026.6.x requires Node >=22.19.0
ENV NODE_VERSION=22.22.3
RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) NODE_ARCH="x64" ;; \
         arm64) NODE_ARCH="arm64" ;; \
         *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && apt-get update && apt-get install -y xz-utils ca-certificates rclone \
    && rm -rf /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    && curl -fsSLk https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz -o /tmp/node.tar.xz \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version \
    && npm --version

# Install OpenClaw (formerly clawdbot/moltbot)
# Pin to specific version for reproducible builds
RUN npm install -g openclaw@2026.6.5 \
    && openclaw --version

# The Slack channel was externalized from core to a plugin in OpenClaw 2026.5.12
# (versioned in lockstep with core). Without it the gateway boots fine but never
# connects to Slack. Install at build time; it lands in /root/.openclaw/npm/
# (kept in the image) and writes a plugins entry into openclaw.json — remove the
# config file afterwards so the first-boot onboard/restore logic in
# start-openclaw.sh is unaffected (the R2-restored prod config already carries
# plugins.entries.slack.enabled).
RUN openclaw plugins install @openclaw/slack@2026.6.5 \
    && rm -f /root/.openclaw/openclaw.json

# Create OpenClaw directories
# Legacy .clawdbot paths are kept for R2 backup migration
RUN mkdir -p /root/.openclaw \
    && mkdir -p /root/clawd \
    && mkdir -p /root/clawd/skills

# Copy startup script
# Bump CACHE_BUST to force a new image digest (and thus a container rollout)
# even when no file content changed. A bare comment is NOT enough: comments
# don't change layer hashes, so wrangler ends up pushing an identical digest
# and the running instance is never replaced.
ENV CACHE_BUST=2026-06-12-v39-cdp-browser-rendering
COPY start-openclaw.sh /usr/local/bin/start-openclaw.sh
RUN chmod +x /usr/local/bin/start-openclaw.sh

# Copy custom skills into the agent workspace skills dir. OpenClaw discovers
# skills by scanning <agents.defaults.workspace>/skills, and this deployment's
# R2-persisted config sets workspace = /root/.openclaw/workspace — NOT the
# /root/clawd default this repo originally assumed (skills copied there were
# never discovered). The R2 restore of the openclaw/ prefix covers this path
# and overwrites matching files, so keep r2:moltbot-data/openclaw/workspace/skills/
# in sync when changing skills here.
COPY skills/ /root/.openclaw/workspace/skills/

# Set working directory
WORKDIR /root/clawd

# Expose the gateway port
EXPOSE 18789
