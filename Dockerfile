# ---- Build stage ----
ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29
ARG ALPINE_VERSION=3.22

FROM elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}-alpine AS builder

# Build tools needed for NIFs / native deps (git for hex deps from git, build-base for C compilation)
RUN apk add --no-cache build-base git

ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Cache deps separately from app code
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

COPY lib lib
COPY config config

RUN mix compile

# Build the release
RUN mix release

# ---- Runtime stage ----
FROM alpine:${ALPINE_VERSION} AS runtime
RUN apk add --no-cache libstdc++ openssl ncurses-libs libgcc liblksctp

ENV LANG=C.UTF-8 \
    MIX_ENV=prod

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
USER app

# Copy just the compiled release, not the whole build tree
COPY --from=builder --chown=app:app /app/_build/prod/rel/eljobs ./

ENV HOME=/app

CMD ["bin/eljobs", "start"]
