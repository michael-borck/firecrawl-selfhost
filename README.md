# firecrawl-selfhost

A minimal assembly of **self-hosted Firecrawl** plus existing open-source clients. No custom crawler, no fork, no subscription. This folder is the glue: compose overlays, a setup script, and a Makefile.

Last verified: 2026-11-20, macOS 26.6, Docker 28/29, Node 26.

## What runs

| Service | Image | Host address | Auth |
| --- | --- | --- | --- |
| [Firecrawl API](https://github.com/firecrawl/firecrawl) | `ghcr.io/firecrawl/firecrawl:latest` | `0.0.0.0:3002` | none by default |
| Playwright | `ghcr.io/firecrawl/playwright-service:latest` | internal | |
| Queue DB | `ghcr.io/firecrawl/nuq-postgres:latest` | internal | |
| Redis, RabbitMQ, FoundationDB | upstream | internal | |
| SearXNG (search) | `searxng/searxng:latest` | `127.0.0.1:8888` | |
| [Firecrawl UI](https://github.com/obeone/firecrawl-ui) | `obeoneorg/firecrawl-ui` | `127.0.0.1:8080` | |
| Caddy gate (optional) | `caddy:2-alpine` | `0.0.0.0:3002` | bearer token |

Clients that talk to it:

- **Web UI** — [obeone/firecrawl-ui](https://github.com/obeone/firecrawl-ui), a static Vue app, settings in `localStorage`.
- **CLI** — official `firecrawl-cli` via `npx`.
- **Agent** — official `firecrawl-mcp`, pointed at the local API.
- **Desktop** — use Chrome/Edge "Install page as app" or Safari "Add to Dock" on `:8080`. No Tauri app exists.
- **TUI** — none. The CLI is the terminal interface.

## Files here

| File | Purpose |
| --- | --- |
| `scripts/selfhost.sh` | Clones the pinned Firecrawl release into `.firecrawl/`, writes `.env`, starts compose, waits for health. |
| `compose.prebuilt.yml` | Uses GHCR images instead of compiling. |
| `compose.search.yml` | Adds SearXNG and points Firecrawl at it. |
| `compose.auth.yml` | Moves the API off the host port and puts Caddy in front. |
| `Caddyfile` | Bearer-token check, then reverse proxy to the API. |
| `searxng/settings.yml` | Enables the JSON API that Firecrawl needs. |
| `Makefile` | Shortcuts for server, UI, and the official CLI. |
| `.env.example` | Client-side variables (`FIRECRAWL_BASE_URL`, `FIRECRAWL_API_KEY`). |
| `.firecrawl/` | Generated: upstream clone, `.env`, `.token`, `.searxng-secret`, compose files. Gitignored. Safe to delete. |

## First run

Requirements: Docker Desktop with Compose v2, Node 22+ for the CLI/MCP via `npx`. No `npm install`, no account, no API key.

```sh
make up-search      # Firecrawl + SearXNG
make ui-up          # UI on http://127.0.0.1:8080
open http://127.0.0.1:8080
```

In the UI: gear icon → Base URL `http://localhost:3002`, API key blank → Test connection. CORS on the API is open, so the browser calls it directly.

## Daily use

```sh
make start                     # start server + UI (keyless)
make start-auth                # start server + UI (bearer gate)
make stop                      # stop server + UI
make logs                      # follow API logs

make scrape URL=https://example.com
make map URL=https://example.com
make search Q="rtx 5090 price"
```

Equivalent CLI form, no install:

```sh
npx -y firecrawl-cli@latest --api-url http://localhost:3002 scrape https://example.com
npx -y firecrawl-cli@latest --api-url http://localhost:3002 search "rtx 5090 price" --scrape
```

Persist the endpoint and silence telemetry:

```sh
export FIRECRAWL_API_URL=http://localhost:3002
export FIRECRAWL_NO_TELEMETRY=1
```

## MCP (agent access)

Already added to `~/.config/opencode/opencode.json`:

```json
"firecrawl": {
  "enabled": true,
  "type": "local",
  "command": ["npx", "-y", "firecrawl-mcp@3.40.0"],
  "environment": {
    "FIRECRAWL_API_URL": "http://localhost:3002",
    "FIRECRAWL_NO_TELEMETRY": "1"
  }
}
```

Restart opencode after editing config. Generic MCP clients use the same command and env in their `mcpServers` block.

Working tools against self-host: `firecrawl_scrape`, `firecrawl_crawl`, `firecrawl_map`, `firecrawl_search`. The server also lists cloud-only tools (`firecrawl_agent`, `firecrawl_interact`, monitors, Alexandria); calls to those fail because the self-hosted stack does not include them. MCP returns page text into the model context, which is fine for a few pages and wasteful for hundreds.

## Run the server on another machine (LAN)

The API binds `0.0.0.0:3002`, so any device on the network can reach it. On the server box run `make up-search`; on clients set:

```sh
export FIRECRAWL_API_URL=http://192.168.1.50:3002
```

and in the UI use `http://192.168.1.50:3002` as the Base URL.

Self-hosted Firecrawl has **no built-in API key**. With `USE_DB_AUTHENTICATION=false` the auth layer returns success without reading the header (`apps/api/src/lib/withAuth.ts`), so a key typed into the UI is ignored. Protect it one of two ways:

```sh
make up-auth        # Caddy in front, requires Authorization: Bearer <token>
```

- Token is generated once into `.firecrawl/.token`.
- UI: paste the token into the API key field.
- CLI/MCP: `export FIRECRAWL_API_KEY=$(cat .firecrawl/.token)`.
- curl: `-H "Authorization: Bearer $(cat .firecrawl/.token)"`.
- Verified: no/incorrect token → 401, correct token → 200. The official CLI does send the bearer header to custom API URLs.

Alternative: skip the proxy and put the server on Tailscale/WireGuard. Never port-forward a keyless instance to the internet.

To serve the UI from the server box too:

```sh
UI_BIND=0.0.0.0 make ui-up
```

## Search

Self-hosted resolution order: Fire-engine (not configured), then `SEARXNG_ENDPOINT`, then DuckDuckGo scraping. `make up-search` starts SearXNG and sets `SEARXNG_ENDPOINT=http://searxng:8080`. SearXNG is published only on `127.0.0.1:8888`, for debugging.

Search returns links and snippets. Turning results into a table is extraction: scrape each result, then apply selectors or an LLM schema. The self-hosted stack has no LLM provider configured; point `OPENAI_BASE_URL` at Ollama or an OpenAI-compatible endpoint if you want JSON formats.

## Not included (Firecrawl Cloud only)

Agent, Interact, Browser, screenshots, page actions, managed proxy/anti-bot, and Alexandria data providers. Core scrape, crawl, map, batch scrape, documents (PDF/DOCX), and search run locally.

## Images: prebuilt vs source

Default is prebuilt `ghcr.io/firecrawl/*:latest`, pulled by `compose.prebuilt.yml`. It is not pinned to the clone's tag; the API contract is stable, but `latest` can drift.

Building from source failed on the Crucial X9 external drive with `failed to xattr ._.dockerignore: operation not permitted` (exFAT AppleDouble files). To build the pinned release, clone onto a local disk:

```sh
./scripts/selfhost.sh --search --build      # compiles v2.11.162
```

`compose.prebuilt.yml` uses `build: !reset null` to remove the base compose build directives; keep that if you edit it.

## Verify

```sh
docker ps --format '{{.Names}}\t{{.Status}}' | grep firecrawl
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3002/v0/health/readiness   # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/                     # 200
npx -y firecrawl-cli@latest --api-url http://localhost:3002 scrape https://example.com
```

## Troubleshooting

- **API container restarts or no health**: `make logs`. The first start takes ~30–60s.
- **`failed to xattr` during build**: external/exFAT drive. Use prebuilt images or `--build` from an internal disk.
- **Port 3002 already in use**: leftover Caddy gateway from `make up-auth`. Run `make down`, then the mode you want. `selfhost.sh` uses `--remove-orphans`.
- **UI shows connection errors**: Base URL must be reachable from the browser, not from inside Docker. Use `http://localhost:3002` locally, `http://<server-ip>:3002` on the LAN.
- **Empty search results**: check `docker ps` for SearXNG and `docker compose ... logs searxng`. Without it, Firecrawl falls back to DuckDuckGo and may rate-limit.
- **MCP tools missing**: restart opencode. Confirm with `npx -y firecrawl-mcp@3.40.0` and `FIRECRAWL_API_URL` set.
- **Auth enabled and everything is 401**: the token is in `.firecrawl/.token`; pass it as a bearer header. Delete that file and rerun `make up-auth` to rotate.

## Idle cost and stopping

Measured idle on this machine (Apple Silicon, Docker Desktop):

| Container | RAM |
| --- | --- |
| `firecrawl-api-1` | 2.6 GB |
| `firecrawl-playwright-service-1` | 300 MB |
| `firecrawl-rabbitmq-1` | 351 MB |
| `firecrawl-searxng-1` | 159 MB |
| `firecrawl-nuq-postgres-1` | 113 MB |
| `firecrawl-foundationdb-1` | 68 MB |
| `firecrawl-redis-1` | 13 MB |
| `firecrawl-ui` | 7 MB |

Total is about **3.5 GB RAM and ~0.1 CPU core**, not small. The API process is almost all of it. Lowering `NUM_WORKERS_PER_QUEUE` to 2 did not reduce it in testing, so the default is kept.

```sh
make stop        # stops server containers and the UI
```

Restart with `make start` (keyless) or `make start-auth` (token gate). Stopping does not delete images, the `.firecrawl` clone, or Postgres data; containers are recreated in a few seconds.

`firecrawl-foundationdb-1` is unused unless `NUQ_BACKEND=fdb`. Stopping it saves ~68 MB:

```sh
docker stop firecrawl-foundationdb-1
```

Nothing starts automatically after a reboot (the compose services have no restart policy), so a reboot leaves the API down. Run `make start` when you need it again.

For a lighter setup with no Docker at all, `firecrawl-local` is a single Rust binary (tens of MB) that does scrape, crawl, and map, but not search.

## Cleanup

```sh
make stop           # stop server and UI
make clean          # also deletes .firecrawl/ and out/
```

## Licensing and conduct

[Firecrawl](https://github.com/firecrawl/firecrawl) core is AGPL-3.0 (SDKs MIT). Running it locally or internally is unaffected. If you modify it and expose it as a hosted service, AGPL requires publishing your changes. The UI ([obeone/firecrawl-ui](https://github.com/obeone/firecrawl-ui)) is a separate third-party project.

Crawling public pages is generally lawful, but terms of service, `robots.txt`, copyright, and personal-data rules still apply. Do not bypass logins, paywalls, or CAPTCHAs, and do not hammer a site.

## History / decisions

- `crawl.py` was removed. The official CLI covers scrape, crawl, map, search, and more, and works against a custom `--api-url` with no key or login.
- A Tauri or TUI client was considered and dropped. The web UI plus CLI covers both needs.
- The GPU price table was a demo, not a requirement. No per-retailer extraction is included.
