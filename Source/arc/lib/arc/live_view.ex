# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Arc.LiveView do
    @moduledoc """
    The Arc commands and queries, called in-process from a LiveView.

    LiveView does not use the HTTP contract or generated TypeScript: it calls the same pipelines
    the HTTP host does, so authorization, validation and recording behave identically on both.

        defmodule MyAppWeb.AuthorsLive do
          use MyAppWeb, :live_view
          use Arc.LiveView, application: MyApp.Arc

          def mount(_params, _session, socket) do
            {:ok,
             socket
             |> assign_observable(:authors, MyApp.Authors.Listing.Authors, :live_authors)
             |> assign_form(:form, MyApp.Authors.Registration.RegisterAuthor)}
          end

          def handle_event("validate", %{"command" => params}, socket),
            do: {:noreply, validate_form(socket, :form, params)}

          def handle_event("save", %{"command" => params}, socket) do
            case submit_form(socket, :form, params) do
              {:ok, _result, socket} -> {:noreply, put_flash(socket, :info, "Registered")}
              {:error, socket} -> {:noreply, socket}
            end
          end
        end

    ## Who is the caller

    The principal is read from the socket's assigns each time a command or query runs, not once
    at mount, so a signed-out or demoted user is caught on the next call. By default Arc reads
    `assigns.arc_principal`, then `assigns.current_scope.user`, then `assigns.current_user`. Pass
    `principal: {Module, :function}` to `use Arc.LiveView` to resolve it your own way; the
    function receives the socket and returns an `Arc.Principal`.

    ## Observable queries

    `assign_observable/5` keeps an assign current. The subscription is a process that ends with the
    LiveView, and the application must be started (`MyApp.Arc` in your supervision tree).
    """

    import Phoenix.Component, only: [assign: 3]
    import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

    alias Arc.{CommandResult, QueryResult, Subscription}
    alias Arc.LiveView.Form

    @doc false
    defmacro __using__(opts) do
      application = Keyword.fetch!(opts, :application)
      principal = Keyword.get(opts, :principal)

      quote do
        import Arc.LiveView
        on_mount({Arc.LiveView, {:default, unquote(application), unquote(principal)}})
      end
    end

    @doc false
    def on_mount({:default, application, principal}, _params, _session, socket) do
      socket =
        socket
        |> assign(:arc_application, application)
        |> assign(:arc_principal_resolver, principal)
        |> assign(:arc_subscriptions, %{})
        |> attach_hook(:arc_query_results, :handle_info, &handle_info/2)

      {:cont, socket}
    end

    defp handle_info({:arc_query_result, key, %QueryResult{} = result}, socket)
         when is_atom(key) do
      case Map.get(socket.assigns.arc_subscriptions, key) do
        {_pid, many?} ->
          {:halt, socket |> assign(key, data(result, many?)) |> assign(result_key(key), result)}

        nil ->
          {:cont, socket}
      end
    end

    defp handle_info(_message, socket), do: {:cont, socket}

    @doc "Builds the Arc context for the current caller."
    @spec context(Phoenix.LiveView.Socket.t(), keyword()) :: Arc.Context.t()
    def context(socket, opts \\ []) do
      application = socket.assigns.arc_application

      Arc.context(
        application,
        Keyword.merge([principal: principal(socket), tenant: socket.assigns[:arc_tenant]], opts)
      )
    end

    defp principal(socket) do
      case socket.assigns[:arc_principal_resolver] do
        {module, function} -> apply(module, function, [socket])
        nil -> from_assigns(socket.assigns)
      end
    end

    defp from_assigns(%{arc_principal: %Arc.Principal{} = principal}), do: principal

    defp from_assigns(%{current_scope: %{user: %{id: _} = user}}), do: from_user(user)
    defp from_assigns(%{current_user: %{id: _} = user}), do: from_user(user)
    defp from_assigns(_), do: Arc.Principal.anonymous()

    defp from_user(%{id: id} = user) do
      Arc.Principal.new(to_string(id), to_string(Map.get(user, :name, Map.get(user, :email, id))),
        roles: Map.get(user, :roles, [])
      )
    end

    # Identity

    @doc """
    Assigns the caller's `Arc.Identity.Result` (the same data `GET /.cratis/me` serves) under `key`.

    An anonymous caller gets a result with `authenticated?: false`. An application without an
    identity provider gets empty details. Identity is presentation data, never an authorization
    decision; commands and queries authorize themselves.
    """
    @spec assign_identity(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
    def assign_identity(socket, key \\ :identity) do
      assign(socket, key, identity(socket))
    end

    @doc "The caller's `Arc.Identity.Result`."
    @spec identity(Phoenix.LiveView.Socket.t()) :: Arc.Identity.Result.t()
    def identity(socket),
      do: Arc.Identity.resolve(socket.assigns.arc_application, principal(socket))

    # Queries

    @doc """
    Runs a query once and assigns its data to `key`, and the full `Arc.QueryResult` to
    `:<key>_result`. A query that fails assigns an empty list or `nil`.
    """
    @spec assign_query(Phoenix.LiveView.Socket.t(), atom(), module(), atom(), map(), keyword()) ::
            Phoenix.LiveView.Socket.t()
    def assign_query(socket, key, read_model, query, args \\ %{}, opts \\ []) do
      {context_opts, query_opts} = Keyword.split(opts, [:tenant])
      ctx = context(socket, context_opts)
      descriptor = read_model.__arc__()
      q = find_query!(descriptor, query)
      raw = Map.new(args, fn {k, v} -> {Arc.Naming.camel(k), v} end)
      result = Arc.Pipeline.execute_query(descriptor, q, raw, ctx, query_opts)

      socket
      |> assign(key, data(result, q.many?))
      |> assign(result_key(key), result)
    end

    @doc """
    Keeps `key` current: assigns the data now (so the connected render never flashes empty) and
    again whenever the query's watched read models change or its topics are notified. Before the
    socket connects, it is a one-shot read.
    """
    @spec assign_observable(
            Phoenix.LiveView.Socket.t(),
            atom(),
            module(),
            atom(),
            map(),
            keyword()
          ) ::
            Phoenix.LiveView.Socket.t()
    def assign_observable(socket, key, read_model, query, args \\ %{}, opts \\ []) do
      if connected?(socket) do
        descriptor = read_model.__arc__()
        q = find_query!(descriptor, query)
        raw = Map.new(args, fn {k, v} -> {Arc.Naming.camel(k), v} end)

        case Map.get(socket.assigns.arc_subscriptions, key) do
          nil -> :ok
          {pid, _many?} -> Subscription.stop(pid)
        end

        spec = %{
          owner: self(),
          id: key,
          descriptor: descriptor,
          query: q,
          args: raw,
          ctx: context(socket),
          opts: opts
        }

        case Subscription.start(socket.assigns.arc_application, spec) do
          {:ok, pid} ->
            subscriptions = Map.put(socket.assigns.arc_subscriptions, key, {pid, q.many?})

            socket
            |> assign(:arc_subscriptions, subscriptions)
            |> assign_query(key, read_model, query, args, opts)

          {:error, reason} ->
            raise "Arc could not subscribe to #{inspect(read_model)}.#{query}: #{inspect(reason)}. Is #{inspect(socket.assigns.arc_application)} started in the supervision tree?"
        end
      else
        assign_query(socket, key, read_model, query, args, opts)
      end
    end

    defp find_query!(descriptor, name) do
      Enum.find(descriptor.queries, &(&1.name == name)) ||
        raise ArgumentError, "#{inspect(descriptor.module)} has no query #{inspect(name)}"
    end

    defp data(%QueryResult{data: data} = result, many?) do
      if QueryResult.success?(result) and data != nil, do: data, else: empty(many?)
    end

    defp empty(true), do: []
    defp empty(false), do: nil

    defp result_key(key), do: String.to_atom("#{key}_result")

    # Commands

    @doc """
    Executes a command through the full pipeline as the current caller.

    Returns `{:ok, result}` when the command succeeded, otherwise `{:error, result}`.
    """
    @spec execute(Phoenix.LiveView.Socket.t(), struct() | {module(), map()}, keyword()) ::
            {:ok, CommandResult.t()} | {:error, CommandResult.t()}
    def execute(socket, command, opts \\ []) do
      {pipeline_opts, context_opts} = Keyword.split(opts, [:validate_only])
      {module, input} = normalize(command)

      result =
        Arc.Pipeline.execute_command(module, input, context(socket, context_opts), pipeline_opts)

      if CommandResult.success?(result), do: {:ok, result}, else: {:error, result}
    end

    defp normalize(%{__struct__: module} = command), do: {module, command}
    defp normalize({module, wire}), do: {module, wire}

    # Forms

    @doc """
    Assigns an empty `Phoenix.HTML.Form` for a command under `key`. Pass `params` to prefill it.
    """
    @spec assign_form(Phoenix.LiveView.Socket.t(), atom(), module(), map()) ::
            Phoenix.LiveView.Socket.t()
    def assign_form(socket, key, command, params \\ %{}) do
      assign(socket, key, Phoenix.Component.to_form(Form.new(command, params), as: :command))
    end

    @doc """
    Validates `params` against the command (authorization, declarative rules, `validate/2`)
    without recording anything, and assigns the form with its errors under `key`.
    """
    @spec validate_form(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
    def validate_form(socket, key, params) do
      form = socket.assigns[key].source

      form =
        Form.validate(form, params, fn input -> run_validation(socket, form.command, input) end)

      assign(socket, key, Phoenix.Component.to_form(form, as: :command))
    end

    @doc """
    Executes the command with `params` and updates the form under `key`.

    Returns `{:ok, result, socket}` on success, or `{:error, socket}` with the errors on the form.
    """
    @spec submit_form(Phoenix.LiveView.Socket.t(), atom(), map()) ::
            {:ok, CommandResult.t(), Phoenix.LiveView.Socket.t()}
            | {:error, Phoenix.LiveView.Socket.t()}
    def submit_form(socket, key, params) do
      form = socket.assigns[key].source

      case Form.submit(form, params, fn input -> execute(socket, {form.command, input}) end) do
        {:ok, result} ->
          {:ok, result,
           assign(socket, key, Phoenix.Component.to_form(Form.new(form.command), as: :command))}

        {:error, form} ->
          {:error, assign(socket, key, Phoenix.Component.to_form(form, as: :command))}
      end
    end

    defp run_validation(socket, command, input) do
      Arc.Pipeline.execute_command(command, input, context(socket), validate_only: true)
    end
  end
end
