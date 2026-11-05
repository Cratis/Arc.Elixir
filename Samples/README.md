# Samples

Runnable samples of Arc for Elixir. Each sample has a `run.sh`: `./run.sh` starts it, `./run.sh test` tests it. `./run-tests.sh` here tests all of them, the way CI does.

Requirements: Elixir 1.18+, Node.js 22+. Chronicle is needed to *run* `plug` and `phoenix` (tests use its in-memory kernel); Docker is needed for the showcase's MongoDB page only.

| Sample | What it shows | Start | Port |
| --- | --- | --- | --- |
| [`plug`](plug) | The smallest Arc app: a counter, Bandit and a Plug router | `./run.sh` | 4001 |
| [`phoenix`](phoenix) | The HTTP contract, LiveView, rules, a constraint, role authorization, an observable query, proxy generation, the built React app | `./run.sh` or `./run.sh dev` | 4000 / 5173 |
| [`frontend`](frontend) | A React app on the proxies the Phoenix sample generates: live list, validated command, identity switcher | `./run.sh dev` | 5173 |
| [`showcase`](showcase) | The .NET Arc samples ported: ticker, live feed, query showcase, authentication, change stream, observable collections, cross-cutting authorization, MongoDB with tenancy; WebSocket and SSE hubs, delta mode | `./run.sh` or `./run.sh dev` | 4002 / 5174 |

## Chronicle for `plug` and `phoenix`

```shell
docker run -d --name chronicle -p 127.0.0.1:35000:35000 cratis/chronicle:latest-development
```

Override with `CHRONICLE_CONNECTION_STRING`. See [the samples guide](../Documentation/samples.md) for details.

## plug

`./run.sh` serves the contract at `http://localhost:4001`. It uses Arc without Phoenix: `Arc.Plug` inside a Plug router.

## phoenix

`./run.sh` starts Chronicle if needed, builds the React app into `priv/spa` and serves it, with the LiveView page at `/live/authors`, on `http://localhost:4000`. `./run.sh dev` runs Phoenix with the hot reload app on `http://localhost:5173`. Compiling writes TypeScript proxies into `frontend/src/arc`. There is no route for `/` until the React app is built, which `./run.sh` does; plain `mix phx.server` answers 404 there.

## frontend

`./run.sh dev` runs Vite against the Phoenix sample; `./run.sh test` type-checks and builds.

## showcase

`./run.sh` starts MongoDB (a one-node replica set via `docker compose`), builds the React app and serves everything on `http://localhost:4002`. `./run.sh dev` runs the server plus Vite on `http://localhost:5174` for live editing.

The toolbar switches transport (WebSocket or SSE), connection count, direct mode, transfer mode (full or delta), tenant (`acme`, `globex`, default) and sign-in. Each feature is a vertical slice: `lib/samples/<feature>` holds its Elixir, its generated TypeScript proxies and its React page (see [Vertical slices](../Documentation/vertical-slices.md)); the app shell is in `frontend/`. Set `MONGODB_URL` or `PORT` to override defaults. Without MongoDB every page works except the MongoDB one, and its tests are skipped.
