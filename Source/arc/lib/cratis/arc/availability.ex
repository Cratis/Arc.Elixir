# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability do
  @moduledoc """
  Availability: which parts of an application (commands and queries, grouped in modules, features and
  slices) exist for the caller in front of you. It is the same model as Arc for .NET and Screenplay:
  audiences, blocks (`for`, `when`, `with`, `not`), gates on module, feature, slice, command and query,
  and suspension.

  It is one gate, and it runs first: before `Cratis.Arc.Filter`, authorization, binding and validation. A
  part that is not available answers `403` with the reason `NotAvailable`, a suspended part `403` with
  `Suspended`; a decision that cannot be made (a store that is down) is a retryable error, `503`,
  never a denial.

  ## Declaring

  A command, a read model or a single query declares its gate with `available`:

      defmodule MyApp.Fleet.Vessels.DockVessel do
        use Cratis.Arc.Command
        available for: ["Plus", "Admin"], with: "Reported", when: MyApp.HasPaidInvoice
      end

  The vocabulary (audiences, blocks, scopes, provided values) lives in a
  `Cratis.Arc.Availability.Definition`. Configure it, and where audiences and suspensions come from:

      config :my_app, MyApp.Arc,
        availability: [
          definition: MyApp.Availability,
          audience_source: Cratis.Arc.Availability.Memory,
          suspension_source: Cratis.Arc.Availability.Memory,
          pubsub: MyApp.PubSub
        ]

  Words: audiences are *granted* and *withdrawn*; parts are *suspended* and *resumed*.

  ## Sources

    * `Cratis.Arc.Availability.AudienceSource` - who holds which audience (tenant and user are given)
    * `Cratis.Arc.Availability.SuspensionSource` - the paths an operator suspended
    * `Cratis.Arc.Availability.Memory` - both, in memory, for specifications and samples

  A source tells the application when it changes with `changed/1`: open sessions of
  `/.cratis/availability` decide again, on every node when `:pubsub` is configured.
  """

  alias Cratis.Arc.Availability.{Development, Engine, Paths}
  alias Cratis.Arc.Context

  @topic :arc_availability

  @doc "The Arc notifier topic that open availability observers listen to."
  @spec topic() :: atom()
  def topic, do: @topic

  @doc "The availability configuration of an application, or `nil`."
  @spec config(module()) :: keyword() | nil
  def config(app), do: Keyword.get(app.config(), :availability)

  @doc "Whether the application configured availability."
  @spec enabled?(module()) :: boolean()
  def enabled?(app), do: config(app) != nil

  @doc """
  Tells the application that audiences or suspensions changed. Observers decide again on this node
  and, when a `:pubsub` is configured, on every node.
  """
  @spec changed(module()) :: :ok
  def changed(app) do
    Cratis.Arc.Notifier.notify(app, @topic)

    with config when is_list(config) <- config(app),
         pubsub when not is_nil(pubsub) <- config[:pubsub],
         true <- Code.ensure_loaded?(Phoenix.PubSub) do
      Phoenix.PubSub.broadcast_from(
        pubsub,
        self(),
        pubsub_topic(app),
        {:arc_availability_changed, app}
      )
    end

    :ok
  end

  @doc false
  def pubsub_topic(app), do: "arc:availability:" <> inspect(app)

  # --- Building the parts -------------------------------------------------------------------

  @doc false
  def build(config, commands, read_models) do
    availability = config[:availability]
    definition = definition(availability)
    segments = config[:segments_to_skip]

    commands =
      for d <- commands do
        part(d, "command", inspect(d.module), segments, definition, [d.availability])
      end

    queries =
      for d <- read_models, q <- d.queries do
        part(d, "readModel", Cratis.Arc.Descriptor.query_name(d, q), segments, definition, [
          d.availability,
          q.availability
        ])
      end

    parts = commands ++ queries

    %{
      definition: definition,
      parts: Map.new(parts, &{&1.key, &1}),
      list: Enum.sort_by(parts, & &1.name),
      conditions: conditions(definition, parts)
    }
  end

  defp definition(nil), do: Cratis.Arc.Availability.Definition.empty()

  defp definition(config) do
    case config[:definition] do
      nil -> Cratis.Arc.Availability.Definition.empty()
      module -> module.__availability__()
    end
  end

  defp part(descriptor, kind, name, segments, definition, own) do
    {module, feature, slice} = Cratis.Arc.Descriptor.slice_location(descriptor, segments)
    namespace = Enum.join(descriptor.namespace, ".")

    scopes =
      definition.scopes
      |> Enum.filter(
        &(namespace == &1["namespace"] or String.starts_with?(namespace, &1["namespace"] <> "."))
      )
      |> Enum.sort_by(&{String.length(&1["namespace"]), &1["namespace"]})
      |> Enum.map(& &1["gate"])

    key =
      case kind do
        "command" -> {:command, descriptor.module}
        _ -> {:query, descriptor.module, name}
      end

    %{
      key: key,
      name: name,
      kind: kind,
      module: module,
      feature: feature,
      slice: slice,
      path: Paths.for_part(module, feature, slice, name),
      owner: inspect(descriptor.module),
      owner_path: Paths.for_part(module, feature, slice, inspect(descriptor.module)),
      gates: scopes ++ Enum.reject(own, &is_nil/1)
    }
  end

  # Named conditions by name, from every gate of every part, scope and block.
  defp conditions(definition, parts) do
    gates =
      Enum.flat_map(parts, & &1.gates) ++
        Enum.map(definition.blocks, & &1["gate"]) ++ Enum.map(definition.scopes, & &1["gate"])

    gates |> Enum.flat_map(&named/1) |> Map.new(fn name -> {name, Module.concat([name])} end)
  end

  defp named(%{"kind" => "named", "name" => name}), do: [name]
  defp named(%{"items" => items}), do: Enum.flat_map(items, &named/1)
  defp named(%{"condition" => condition}), do: named(condition)
  defp named(_), do: []

  # --- Deciding ------------------------------------------------------------------------------

  @typedoc "What the hook decided."
  @type verdict :: :ok | {:denied, String.t()} | {:error, term()}

  @doc "Decides a command for a context, over the arguments it was sent with."
  @spec check_command(Context.t(), module(), map() | struct()) :: verdict()
  def check_command(%Context{application: nil}, _module, _input), do: :ok
  def check_command(ctx, module, input), do: check(ctx, {:command, module}, input)

  @doc "Decides a query for a context, over the arguments it was asked with."
  @spec check_query(
          Context.t(),
          Cratis.Arc.Descriptor.t(),
          Cratis.Arc.Descriptor.Query.t(),
          map()
        ) :: verdict()
  def check_query(%Context{application: nil}, _descriptor, _query, _args), do: :ok

  def check_query(ctx, descriptor, query, args),
    do:
      check(
        ctx,
        {:query, descriptor.module, Cratis.Arc.Descriptor.query_name(descriptor, query)},
        args
      )

  defp check(ctx, key, arguments) do
    app = ctx.application
    state = Cratis.Arc.Application.state(app)

    with %{parts: parts} <- state[:availability],
         %{} = part <- parts[key] do
      case Development.switch(Development.current(app), part) do
        :off ->
          {:denied, "NotAvailable"}

        :on ->
          :ok

        :none ->
          if decidable?(state, part), do: decide(app, ctx, state, part, arguments), else: :ok
      end
    else
      _ -> :ok
    end
  end

  # A part nothing gates, with nothing suspendable, never reaches a source.
  defp decidable?(state, part),
    do: part.gates != [] or state.config[:availability][:suspension_source] != nil

  defp decide(app, ctx, state, part, arguments) do
    case Engine.decide(part, environment(app, ctx, state, arguments)) do
      {:ok, decision} -> verdict(part, decision)
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  catch
    {:availability_failure, reason} -> {:error, reason}
  end

  defp verdict(_part, :available), do: :ok
  defp verdict(_part, :suspended), do: {:denied, "Suspended"}

  defp verdict(part, {_unavailable, causes}) do
    require Logger
    Logger.debug("Arc availability: #{part.name} is not available (#{Enum.join(causes, "; ")})")
    {:denied, "NotAvailable"}
  end

  @doc false
  def environment(app, ctx, state, arguments) do
    config = state.config[:availability]
    availability = state.availability

    suspended =
      case config[:suspension_source] do
        nil ->
          []

        source ->
          case source.suspended() do
            {:ok, paths} -> paths
            {:error, reason} -> throw({:availability_failure, reason})
          end
      end

    values =
      Map.new(availability.definition.values, fn %{name: name, provider: provider} ->
        {name, provider_fun(provider)}
      end)

    %{
      ambient: ambient(ctx, arguments),
      audiences: fn -> audiences(app, config, availability, ctx) end,
      values: values,
      blocks: Map.new(availability.definition.blocks, &{&1["name"], &1["gate"]}),
      conditions: availability.conditions,
      suspended: suspended
    }
  end

  defp provider_fun(fun) when is_function(fun, 1), do: fun
  defp provider_fun(module) when is_atom(module), do: &module.value/1

  defp ambient(ctx, arguments) do
    # The tenant and the identity come from the server and nothing in the arguments replaces them.
    %{
      "tenant" => ctx.tenant,
      "identity" => %{"user" => ctx.principal.id, "isSystem" => false},
      "arguments" => wire_arguments(arguments)
    }
  end

  defp wire_arguments(%{__struct__: _} = struct),
    do: struct |> Map.from_struct() |> wire_arguments()

  defp wire_arguments(map) when is_map(map),
    do:
      Map.new(map, fn {key, value} -> {key |> to_string() |> Cratis.Arc.Naming.camel(), value} end)

  defp wire_arguments(_other), do: %{}

  defp audiences(app, config, availability, ctx) do
    declared = MapSet.new(availability.definition.audiences, & &1["name"])
    overrides = Development.current(app)

    case held(app, config, ctx) do
      {:ok, names} ->
        {:ok,
         overrides |> Development.audiences(names) |> Enum.filter(&MapSet.member?(declared, &1))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp held(app, config, ctx) do
    case config[:audience_source] do
      nil -> {:ok, []}
      source -> source.grants(%{tenant: ctx.tenant, user: ctx.principal.id, application: app})
    end
  end

  @doc """
  The parts that are not available to the caller of `ctx`, as the `/.cratis/availability` answer
  lists them. `opts` may carry `:part` (a part name) and `:arguments` (a map) to ask about one part.

  Returns `{:ok, [%{name:, module:, feature:, slice:, reason:}]}`, or `{:error, reason}` when a
  decision cannot be made.
  """
  @spec unavailable(Context.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def unavailable(%Context{application: app} = ctx, opts \\ []) do
    state = Cratis.Arc.Application.state(app)

    case state[:availability] do
      nil ->
        {:ok, []}

      availability ->
        parts =
          case opts[:part] do
            nil -> availability.list
            name -> Enum.filter(availability.list, &(&1.name == name))
          end

        arguments = opts[:arguments] || %{}

        overrides = Development.current(app)

        Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
          case decide_switched(app, ctx, state, part, arguments, overrides) do
            :ok ->
              {:cont, {:ok, acc}}

            {:denied, reason} ->
              {:cont, {:ok, [refusal(part, reason) | acc]}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, list} -> {:ok, Enum.reverse(list)}
          error -> error
        end
    end
  end

  defp decide_switched(app, ctx, state, part, arguments, overrides) do
    case Development.switch(overrides, part) do
      :off -> {:denied, "NotAvailable"}
      :on -> :ok
      :none -> decide(app, ctx, state, part, arguments)
    end
  end

  defp refusal(part, reason),
    do: %{
      "name" => part.name,
      "module" => part.module,
      "feature" => part.feature,
      "slice" => part.slice,
      "reason" => reason
    }
end
