FROM oven/bun:1

# Install Node.js (required by Claude Code CLI) and essential tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl ca-certificates git unzip && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Copy app source
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production
COPY tsconfig.json ./
COPY src ./src
COPY prompts ./prompts
COPY commands ./commands
COPY hooks ./hooks
COPY skills ./skills
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Workspace = process.cwd() for ClaudeClaw state
WORKDIR /workspace

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["start", "--telegram", "--trigger", "--replace-existing"]
