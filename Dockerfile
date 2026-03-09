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

# Workspace = process.cwd() for ClaudeClaw state
WORKDIR /workspace

ENTRYPOINT ["bun", "run", "/app/src/index.ts"]
CMD ["start", "--telegram", "--trigger", "--replace-existing"]
