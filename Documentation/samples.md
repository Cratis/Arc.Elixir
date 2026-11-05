---
title: Samples
description: Run the plug, Phoenix and React samples, against a development Chronicle kernel or in the test suite, and see what each one demonstrates.
---

The repository's `Samples` folder holds four applications. Together they cover the smallest possible Arc app, the full Phoenix story, the React client, and the showcase that mirrors the Samples of Arc on .NET.

| Sample | Shows |
| --- | --- |
| `Samples/plug` | The smallest Arc application: a counter, Bandit, a Plug router, no Phoenix |
| `Samples/phoenix` | The HTTP contract, a LiveView page and the built React app served from one Phoenix endpoint; commands with rules, a constraint and role-based authorization; an observable query; opt-in proxy generation |
| `Samples/showcase` | The samples of Arc on .NET, ported: ticker, live feed, query showcase, conditional queries, authentication queries, change stream, observable collections, cross-cutting authorization and MongoDB, on a plain Plug server and a React app with a toolbar for transport (WebSocket or Server-Sent Events), connection count, direct mode, transfer mode (delta or full), tenant and identity |
| `Samples/frontend` | A React app on the generated proxies: a live list, a validated command, and an identity switcher |

## Run them in tests

Every sample has a test suite on Chronicle's in-memory kernel, so you need no kernel to see them work.

```shell
Samples/run-tests.sh
```

It formats, compiles with warnings as errors and tests the Elixir samples, then type-checks and builds the React app against the proxies the Phoenix sample generated.

## Run the Phoenix sample

You need Elixir 1.18, Node.js 22 and Docker.

```shell
docker run -d --name chronicle \
  -p 127.0.0.1:35000:35000 -p 127.0.0.1:27017:27017 \
  cratis/chronicle:latest-development

cd Samples/phoenix
mix deps.get
mix phx.server
```

Compiling writes TypeScript proxies into `Samples/frontend/src/arc`. Then:

- Open <http://localhost:4000/live/authors> for the LiveView page. Add `?as=ed&roles=editor` to sign in as an editor who may rename.
- Run the React app with hot reload, proxied to Phoenix:

  ```shell
  cd ../frontend
  npm ci
  npm run dev
  ```

  Open <http://localhost:5173>.
- Or build the React app and let Phoenix serve it from one origin:

  ```shell
  cd ../frontend
  ARC_SPA_OUT="$PWD/../phoenix/priv/spa" npm run build
  cd ../phoenix
  mix phx.server
  ```

  `./run.sh` in `Samples/phoenix` does all of this, starting Chronicle too; `./run.sh dev` runs Phoenix and the hot reload app together.

  Open <http://localhost:4000>.

Register an author in either UI and watch the other update: both read the same observable query from Chronicle. Try a name shorter than two characters, the reserved name `admin`, and a duplicate name to see the three kinds of rejection.

Set `CHRONICLE_CONNECTION_STRING` to point at a different kernel.

## Run the showcase

You need Elixir 1.18 and Node.js 22. Only the MongoDB page needs Docker; everything else runs with no database, and the ticker, live feed and collections need nothing but this.

```shell
cd Samples/showcase
docker compose up -d          # a one-node MongoDB replica set, for the MongoDB page
mix deps.get
mix run --no-halt             # the server, on http://localhost:4002
```

In a second terminal:

```shell
cd Samples/showcase
npm ci
npm run dev                   # http://localhost:5174, proxied to the server
```

The toolbar changes how the client talks to the server:

- **Transport** switches the multiplexed hub between WebSocket and Server-Sent Events. The pages and their data do not change.
- **Connections** and **Direct mode** change how subscriptions share connections, or bypass the hub for one connection per query.
- **Transfer mode** selects delta or full. The Change Stream page shows what a delta looks like.
- **Tenant** selects `acme`, `globex` or the default. Add an item on the MongoDB page under one tenant and switch: each tenant is a database of its own (`samples`, `samples+acme`, `samples+globex`).
- **Logged in**, **User ID**, **Name** and **Roles** sign in. The Authentication Queries page needs a signed-in user, and the Cross-Cutting Authorization page needs the role `CrossCuttingAuthorization`.

`MONGODB_URL` points the server at another MongoDB and `PORT` at another port. `npm run build` builds the app into `priv/spa`, and the server then serves it itself on one origin.

The sign-in and tenant travel as headers and as cookies, because a WebSocket handshake and an `EventSource` can send cookies but not headers; `Samples.Web.CookieIdentity` turns them back into the headers Arc reads. The sample trusts these unsigned headers so it can show authorization without a user database. A real application authenticates with its own scheme.

## Run the plug sample

```shell
cd Samples/plug
mix deps.get
mix run --no-halt
curl -X POST localhost:4001/api/counting/increment-counter \
  -H 'content-type: application/json' \
  -d '{"id":"7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e","by":2}'
```

## Next steps

- [Get started](get-started.md) walks through the Phoenix sample step by step.
