# Production Phoenix Dockerfile
FROM elixir:1.19.4-otp-27 AS builder

# Install build dependencies
RUN apt-get update && \
    apt-get install -y build-essential git curl && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

# Set build ENV
ENV MIX_ENV=prod

# Copy mix files and fetch dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY . .

# Compile application and build release
RUN mix compile
RUN mix assets.deploy || true
RUN mix release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/init ./

# Expose Phoenix port
EXPOSE 4000

ENV HOME=/app

CMD ["bin/init", "start"]
