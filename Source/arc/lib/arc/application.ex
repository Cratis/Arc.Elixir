# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Application do
  @moduledoc """
  The runtime of one Arc application: discovery, configuration and the processes that serve
  observable queries.

      defmodule MyApp.Arc do
        use Arc.Application, otp_app: :my_app
      end

  Start it in your supervision tree, after the Chronicle client:

      children = [
        {Chronicle.Client, ...},
        MyApp.Arc
      ]

  There is no global configuration. Everything is scoped to the application module, so tests
  and several Arc applications in one VM stay isolated.

  ## Options

  Options are given to `use` and merged over `config :my_app, MyApp.Arc, [...]`.

    * `:otp_app` - (required) the OTP application whose modules are scanned for commands and
      read models (anything defining `__arc__/0`)
    * `:artifacts` - an explicit list of modules instead of scanning `:otp_app`
    * `:route_prefix` - default `"api"`
    * `:segments_to_skip` - leading module-name segments dropped from routes, slice locations
      and proxy folders; default `1` (the application name)
    * `:chronicle` - options given to every Chronicle call, for example `[client: MyApp.Chronicle]`
    * `:authentication` - a list of `Arc.Authentication` handler modules, run in order
    * `:policies` - `[name: PolicyModule]` for `Arc.Policy`
    * `:tenant_header` - default `"x-cratis-tenant-id"`
    * `:correlation_header` - default `"x-correlation-id"`
    * `:max_body_bytes` - request body limit; default `1_000_000`
    * `:introspection` - who may read the `/.cratis/commands` and `/.cratis/queries` catalogs:
      `:authenticated` (default), `:anonymous` or `false` to remove them
    * `:expose_exceptions` - include exception messages and stack traces in results; default
      `false`, which replaces them with a generic message (the detail is always logged)
    * `:identity_details` - a module with `details(principal)` returning a map, served under `/.cratis/me`
  """

  alias Arc.Descriptor

  @key __MODULE__

  @doc false
  defmacro __using__(opts) do
    quote do
      @arc_application_opts unquote(opts)

      @doc false
      def child_spec(init_arg) do
        %{
          id: __MODULE__,
          start: {Arc.Application.Supervisor, :start_link, [__MODULE__, init_arg]},
          type: :supervisor
        }
      end

      @doc "The merged configuration of this application."
      @spec config() :: keyword()
      def config, do: Arc.Application.config(__MODULE__, @arc_application_opts)
    end
  end

  @doc false
  @spec config(module(), keyword()) :: keyword()
  def config(app, compile_opts) do
    otp_app = Keyword.fetch!(compile_opts, :otp_app)
    runtime = Application.get_env(otp_app, app, [])

    [
      route_prefix: "api",
      segments_to_skip: 1,
      chronicle: [],
      authentication: [Arc.Authentication.FromAssigns],
      policies: [],
      tenant_header: "x-cratis-tenant-id",
      correlation_header: "x-correlation-id",
      max_body_bytes: 1_000_000,
      introspection: :authenticated,
      expose_exceptions: false
    ]
    |> Keyword.merge(compile_opts)
    |> Keyword.merge(runtime)
  end

  @doc """
  The artifact descriptors of an application: `%{commands: [...], read_models: [...]}`.
  """
  @spec artifacts(module()) :: %{commands: [Descriptor.t()], read_models: [Descriptor.t()]}
  def artifacts(app) do
    state = state(app)
    %{commands: state.commands, read_models: state.read_models}
  end

  @doc false
  @spec state(module()) :: map()
  def state(app) do
    case :persistent_term.get({@key, app}, nil) do
      nil -> refresh(app)
      state -> state
    end
  end

  @doc false
  @spec refresh(module()) :: map()
  def refresh(app) do
    config = app.config()
    descriptors = discover(config)
    commands = Enum.filter(descriptors, &(&1.kind == :command))
    read_models = Enum.filter(descriptors, &(&1.kind == :read_model))
    opts = [route_prefix: config[:route_prefix], segments_to_skip: config[:segments_to_skip]]

    command_routes = Map.new(commands, &{Descriptor.command_route(&1, opts), &1})

    query_routes =
      for d <- read_models,
          q <- d.queries,
          into: %{},
          do: {Descriptor.query_route(d, q, opts), {d, q}}

    query_names =
      for d <- read_models, q <- d.queries, into: %{}, do: {Descriptor.query_name(d, q), {d, q}}

    ensure_unique!(commands, opts, &Descriptor.command_route(&1, opts), "command")

    ensure_unique!(
      for(d <- read_models, q <- d.queries, do: {d, q}),
      opts,
      fn {d, q} -> Descriptor.query_route(d, q, opts) end,
      "query"
    )

    state = %{
      config: config,
      commands: commands,
      read_models: read_models,
      command_routes: command_routes,
      query_routes: query_routes,
      query_names: query_names
    }

    :persistent_term.put({@key, app}, state)
    state
  end

  @doc false
  @spec policy(module() | nil, atom()) :: module() | nil
  def policy(nil, _name), do: nil
  def policy(app, name), do: Keyword.get(state(app).config[:policies], name)

  defp discover(config) do
    modules =
      case Keyword.fetch(config, :artifacts) do
        {:ok, list} ->
          list

        :error ->
          otp_app = Keyword.fetch!(config, :otp_app)
          Application.load(otp_app)
          Application.spec(otp_app, :modules) || []
      end

    modules
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__arc__, 0)))
    |> Enum.map(& &1.__arc__())
    |> Enum.sort_by(&inspect(&1.module))
  end

  defp ensure_unique!(items, _opts, route_fun, kind) do
    items
    |> Enum.group_by(route_fun)
    |> Enum.each(fn
      {_route, [_]} ->
        :ok

      {route, many} ->
        raise ArgumentError,
              "Duplicate Arc #{kind} route #{route}: #{inspect(Enum.map(many, &label/1))}"
    end)
  end

  defp label({d, q}), do: "#{inspect(d.module)}.#{q.name}"
  defp label(d), do: inspect(d.module)

  defmodule Supervisor do
    @moduledoc false
    use Elixir.Supervisor

    def start_link(app, _init_arg),
      do: Elixir.Supervisor.start_link(__MODULE__, app, name: Module.concat(app, Supervisor))

    @impl true
    def init(app) do
      Arc.Application.refresh(app)

      children = [
        {Registry, keys: :duplicate, name: Arc.Notifier.registry(app)},
        {DynamicSupervisor, name: Arc.Notifier.subscriptions(app), strategy: :one_for_one}
      ]

      Elixir.Supervisor.init(children, strategy: :one_for_one)
    end
  end
end
