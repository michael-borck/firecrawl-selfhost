#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${FIRECRAWL_VERSION:-v2.11.162}"
SRC="$ROOT/.firecrawl"
SEARCH=0
BUILD=0
AUTH=0

for arg in "$@"; do
  case "$arg" in
    --search) SEARCH=1 ;;
    --build) BUILD=1 ;;
    --auth) AUTH=1 ;;
    --version=*) VERSION="${arg#*=}" ;;
    -h|--help)
      echo "usage: $0 [--search] [--build] [--auth] [--version=v2.11.162]"
      echo "  default uses prebuilt ghcr images; --build compiles from source"
      echo "  --auth puts Caddy in front and requires a bearer token"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null || { echo "docker compose v2 is required" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
  echo "cloning firecrawl $VERSION into $SRC"
  git clone --depth 1 --branch "$VERSION" \
    https://github.com/firecrawl/firecrawl.git "$SRC"
fi

if [ ! -f "$SRC/.env" ]; then
  password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
  cat > "$SRC/.env" <<EOF
USE_DB_AUTHENTICATION=false
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$password
POSTGRES_DB=postgres
EOF
  echo "wrote $SRC/.env (authentication disabled, local only)"
fi

compose_args=(-f "$SRC/docker-compose.yaml")

if [ "$BUILD" -eq 0 ]; then
  cp "$ROOT/compose.prebuilt.yml" "$SRC/compose.prebuilt.yml"
  compose_args+=(-f "$SRC/compose.prebuilt.yml")
  echo "using prebuilt ghcr images; pass --build to compile from source"
fi

if [ "$SEARCH" -eq 1 ]; then
  if [ -z "${SEARXNG_SECRET:-}" ]; then
    if [ -f "$SRC/.searxng-secret" ]; then
      SEARXNG_SECRET="$(cat "$SRC/.searxng-secret")"
    else
      SEARXNG_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
      (umask 077; printf '%s' "$SEARXNG_SECRET" > "$SRC/.searxng-secret")
    fi
  fi
  export SEARXNG_SECRET
  mkdir -p "$SRC/searxng"
  cp "$ROOT/searxng/settings.yml" "$SRC/searxng/settings.yml"
  cp "$ROOT/compose.search.yml" "$SRC/compose.search.yml"
  compose_args+=(-f "$SRC/compose.search.yml")
  echo "search enabled through bundled SearXNG"
fi

if [ "$AUTH" -eq 1 ]; then
  if [ -z "${FIRECRAWL_TOKEN:-}" ]; then
    if [ -f "$SRC/.token" ]; then
      FIRECRAWL_TOKEN="$(cat "$SRC/.token")"
    else
      FIRECRAWL_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
      (umask 077; printf '%s' "$FIRECRAWL_TOKEN" > "$SRC/.token")
    fi
  fi
  export FIRECRAWL_TOKEN
  cp "$ROOT/compose.auth.yml" "$SRC/compose.auth.yml"
  cp "$ROOT/Caddyfile" "$SRC/Caddyfile"
  compose_args+=(-f "$SRC/compose.auth.yml")
  echo "auth enabled: send 'Authorization: Bearer $FIRECRAWL_TOKEN'"
  echo "token saved in $SRC/.token"
fi

if [ "$BUILD" -eq 1 ]; then
  echo "building and starting from source (large and slow)"
  docker compose "${compose_args[@]}" up -d --build --remove-orphans
else
  echo "pulling images and starting the stack"
  docker compose "${compose_args[@]}" up -d --remove-orphans
fi

health_args=(-fsS --max-time 2)
if [ "$AUTH" -eq 1 ]; then
  health_args+=(-H "Authorization: Bearer $FIRECRAWL_TOKEN")
fi

echo "waiting for the API on http://localhost:3002"
for _ in $(seq 1 120); do
  if curl "${health_args[@]}" http://localhost:3002/v0/health/readiness >/dev/null 2>&1; then
    echo "ready: http://localhost:3002"
    echo "try: make scrape URL=https://example.com"
    exit 0
  fi
  sleep 2
done

echo "API did not report ready. Inspect logs with:" >&2
echo "  docker compose -f $SRC/docker-compose.yaml logs --tail=200 api" >&2
exit 1
