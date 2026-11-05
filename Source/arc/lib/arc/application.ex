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
    * `:filters` - `Arc.Filter` modules: cross-cutting rules that run for every command and query
    * `:tenant_header` - default `"x-cratis-tenant-id"`; the header the `:header` tenancy resolver
      reads, and the fallback of the `:subdomain` one
    * `:tenancy` - how the tenant is resolved, see `Arc.Tenancy`: `resolver` (`:header`, `:query`,
      `:claim`, `:subdomain`, `:fixed`, `:development` or a module), `header`, `query_parameter`,
      `claim_type`, `base_domain` and `tenant_id`. A named tenant also selects the Chronicle
      namespace of every call made through the context
    * `:correlation_header` - default `"x-correlation-id"`
    * `:max_body_bytes` - request body limit; default `1_000_000`
    * `:introspection` - who may read the discovery routes (`/.cratis/commands`, `/.cratis/queries`,
      `/.cratis/identity-details/schema`, `/.cratis/users`, `/.cratis/tenants`): `:authenticated`
      (default), `:anonymous` or `false` to remove them. `/.cratis/me` is not affected
    * `:expose_exceptions` - include exception messages and stack traces in results; default
      `false`, which replaces them with a generic message (the detail is always logged)
    * `:identity_details` - the `Arc.Identity.Provider` module to use; by default the single
      provider found in `:otp_app`. Without a provider `/.cratis/me` is not served
    * `:trust_forwarded_identity_headers` - let `Arc.Authentication.MicrosoftIdentityPlatform` accept the
      `x-ms-client-principal*` headers; default `false`. Enable only behind an ingress that
      authenticates callers and strips client-supplied identity headers
    * `:forwarded_identity` - signed forwarded identity, see `Arc.Identity.SignedForwarding`:
      `enabled`, `audience`, `keys: [[key_id:, secret_base64:]]`
    * `:on_behalf_of` - acting on behalf of a user, see `Arc.Identity.OnBehalfOf`: `enabled`, `issuer`,
      `audience`, `service`, `clock_skew` (seconds), `signing_keys: [[key_id:, public_key_pem:]]`
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
      filters: [],
      tenant_header: "x-cratis-tenant-id",
      tenancy: [],
      correlation_header: "x-correlation-id",
      max_body_bytes: 1_000_000,
      introspection: :authenticated,
      trust_forwarded_identity_headers: false,
      forwarded_identity: [enabled: false, audience: "", keys: []],
      on_behalf_of: [
        enabled: false,
        issuer: "",
        audience: "",
        service: "",
        clock_skew: 30,
        signing_keys: []
      ],
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
    Arc.Tenancy.validate!(config)
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

    modules = candidate_modules(config)

    state = %{
      config: config,
      commands: commands,
      read_models: read_models,
      command_routes: command_routes,
      query_routes: query_routes,
      query_names: query_names,
      identity_provider: identity_provider(config, modules),
      users_providers: implementing(modules, Arc.Identity.UsersProvider),
      tenants_providers: implementing(modules, Arc.Identity.TenantsProvider)
    }

    :persistent_term.put({@key, app}, state)
    state
  end

  @doc false
  @spec policy(module() | nil, atom()) :: module() | nil
  def policy(nil, _name), do: nil
  def policy(app, name), do: Keyword.get(state(app).config[:policies], name)

  defp candidate_modules(config) do
    case Keyword.fetch(config, :artifacts) do
      {:ok, list} ->
        list

      :error ->
        otp_app = Keyword.fetch!(config, :otp_app)
        Application.load(otp_app)
        Application.spec(otp_app, :modules) || []
    end
  end

  defp discover(config) do
    config
    |> candidate_modules()
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__arc__, 0)))
    |> Enum.map(& &1.__arc__())
    |> Enum.sort_by(&inspect(&1.module))
  end

  # Modules that declare `@behaviour behaviour`, in a stable order.
  defp implementing(modules, behaviour) do
    modules
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) and
        behaviour in (module.module_info(:attributes)[:behaviour] || [])
    end)
    |> Enum.sort_by(&inspect/1)
  end

  defp identity_provider(config, modules) do
    case config[:identity_details] do
      nil ->
        case implementing(modules, Arc.Identity.Provider) do
          [] ->
            nil

          [provider] ->
            provider

          many ->
            raise ArgumentError,
                  "Several identity providers found: #{inspect(many)}. Keep one, or name it with the identity_details option."
        end

      explicit ->
        explicit
    end
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
        {Registry, keys: :unique, name: Arc.Plug.SseHub.registry(app)},
        {Arc.Identity.ReplayCache, app},
        {DynamicSupervisor, name: Arc.Notifier.subscriptions(app), strategy: :one_for_one}
      ]

      Elixir.Supervisor.init(children, strategy: :one_for_one)
    end
  end
end
