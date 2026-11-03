---
title: LiveView
description: Call Arc commands and queries from Phoenix LiveView in process, keep assigns current from observable queries, and bind forms to commands with the standard components.
---

LiveView pages and React apps want the same thing from the backend: run a command, read a query, show what went wrong. Arc lets a LiveView do that by calling the pipeline directly. There is no HTTP hop, no JSON, and no generated TypeScript; authorization, validation and recording behave exactly as they do for the HTTP host.

```elixir
use Phoenix.LiveView
use Arc.LiveView, application: Library.Arc
```

`use Arc.LiveView` imports the helpers below and attaches a hook that applies query updates, so there are no `handle_info` callbacks to write for them.

## Read a query

`assign_query/6` runs a query once and assigns its data. `assign_observable/6` also keeps it current. Both take the socket, an assign key, the read model module, the query name, and optionally arguments.

```elixir
# From: Samples/phoenix/lib/library/web/authors_live.ex
      def mount(_params, session, socket) do
        # The signed-in user lives in the session; Arc reads the principal from the socket on every call.
        socket = if user = session["user"], do: assign(socket, :current_user, user), else: socket

        {:ok,
         socket
         |> assign(:notice, nil)
         |> assign_observable(:authors, Authors, :live_authors)
         |> new_form()}
      end
```

After `mount`, `@authors` holds the list and `@authors_result` the full `Arc.QueryResult`. The assign is always populated, so the connected render never flashes empty; a failed query assigns `[]` (or `nil` for a single-model query).

`assign_observable` subscribes only once the socket is connected, so the static render is a one-shot read. The subscription is a process that ends with the LiveView. The Arc application must be running under your supervision tree.

## Run a command

`execute/3` runs the full pipeline as the current caller and returns `{:ok, result}` or `{:error, result}`.

```elixir
# From: Samples/phoenix/lib/library/web/authors_live.ex
  def handle_event("rename", %{"id" => id}, socket) do
    command = %RenameAuthor{id: id, name: "Renamed #{System.unique_integer([:positive])}"}
    {:noreply, assign(socket, :notice, describe(execute(socket, command)))}
  end

  defp describe({:ok, _result}), do: "Renamed."
  defp describe({:error, %{authorized?: false} = result}),
    do: "Not allowed: #{result.authorization_failure_reason}"

  defp describe({:error, _result}), do: "The rename was rejected."
```

## Forms

A command is a form. `assign_form/4` assigns a `Phoenix.HTML.Form` for a command; the standard `<.form>` and `<.input>` components work with it, and the pipeline's validation results appear on the field they name.

```elixir
# From: Samples/phoenix/lib/library/web/authors_live.ex
      def handle_event("validate", %{"command" => params}, socket),
        do: {:noreply, validate_form(socket, :form, params)}

      def handle_event("register", %{"command" => params}, socket) do
        case submit_form(socket, :form, params) do
          {:ok, _result, socket} -> {:noreply, socket |> new_form() |> assign(:notice, "Registered.")}
          {:error, socket} -> {:noreply, socket}
        end
      end
```

- `validate_form/3` runs authorization and validation without recording anything, so `phx-change` shows errors as the user types.
- `submit_form/3` executes the command. On success it returns the result and resets the form; on failure it returns the socket with the errors on the form.

Form values arrive as strings. Empty strings become `nil` for fields that are not strings, keys are the `snake_case` field names, and a field the form does not include is simply absent. Include the key as a hidden input, as the sample does. A result with no member, an authorization failure or an exception appears under the form's `:base` errors.

## Who is the caller

Arc reads the principal from the socket's assigns each time it runs something, not once at mount, so a signed-out or demoted user is caught on the next call. It looks at `assigns.arc_principal`, then `assigns.current_scope.user`, then `assigns.current_user`. With `phx.gen.auth` that works as is, provided your authentication hook runs in `on_mount` before the page's `mount`.

To resolve it your own way, give the function that takes the socket and returns an `Arc.Principal`:

```elixir
use Arc.LiveView, application: MyApp.Arc, principal: {MyAppWeb.Auth, :arc_principal}
```

## Test it

`Phoenix.LiveViewTest` works unchanged, with `Arc.Test.Case` providing the in-memory kernel:

```elixir
# From: Samples/phoenix/test/library/authors_live_test.exs
      test "the form shows the pipeline's validation errors as you type" do
        {:ok, view, _html} = live(build_conn(), "/live/authors")

        html = view |> form("#register", command: %{name: "A"}) |> render_change()

        assert html =~ "at least 2 characters"
      end
```

See [Testing](testing.md) for the options.

## Limits

There is no stream helper yet: observable queries assign whole lists. The in-memory kernel used by `Arc.Test` has no read-model query surface, so the list stays empty in such tests; see [Testing](testing.md#what-the-in-memory-kernel-cannot-do).

## Next steps

- [Queries](queries.md#observable-queries) for what triggers a re-run.
- [Hosting on Phoenix](hosting/phoenix.md) for the endpoint.
