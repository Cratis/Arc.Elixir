---
title: Samples
description: Run the plug, Phoenix and React samples, against a development Chronicle kernel or in the test suite, and see what each one demonstrates.
---

The repository's `Samples` folder holds three applications. Together they cover the smallest possible Arc app, the full Phoenix story, and the React client.

| Sample | Shows |
| --- | --- |
| `Samples/plug` | The smallest Arc application: a counter, Bandit, a Plug router, no Phoenix |
| `Samples/phoenix` | The HTTP contract, a LiveView page and the built React app served from one Phoenix endpoint; commands with rules, a constraint and role-based authorization; an observable query; opt-in proxy generation |
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
  cd ../phoenix
  mix spa.build
  mix phx.server
  ```

  Open <http://localhost:4000>.

Register an author in either UI and watch the other update: both read the same observable query from Chronicle. Try a name shorter than two characters, the reserved name `admin`, and a duplicate name to see the three kinds of rejection.

Set `CHRONICLE_CONNECTION_STRING` to point at a different kernel.

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
