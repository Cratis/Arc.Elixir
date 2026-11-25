# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Plug.Introspection do
  @moduledoc false

  # The `/.cratis/*` discovery, identity and hub routes.

  import Plug.Conn

  alias Cratis.Arc.Descriptor
  alias Cratis.Arc.Plug.Request

  def call(conn, app, state) do
    case {conn.method, conn.request_path} do
      {"GET", "/.cratis/commands"} ->
        catalog(conn, app, state, build: &commands/2)

      {"GET", "/.cratis/queries"} ->
        catalog(conn, app, state, build: &queries/2)

      {"GET", "/.cratis/structure"} ->
        catalog(conn, app, state, build: &structure/2)

      {"GET", "/.cratis/availability/model"} ->
        development(conn, app, state, fn ->
          catalog(conn, app, state, build: &availability_model(app, &1, &2))
        end)

      {"POST", "/.cratis/availability/overrides"} ->
        development(conn, app, state, fn -> overrides(conn, app, state) end)

      {"GET", "/.cratis/me"} ->
        identity(conn, app, state)

      {"GET", "/.cratis/identity-details/schema"} ->
        catalog(conn, app, state, build: &identity_schema/2)

      {"GET", "/.cratis/users"} ->
        catalog(conn, app, state, build: &users/2, per_user: true)

      {"GET", "/.cratis/tenants"} ->
        catalog(conn, app, state, build: &tenants/2, per_user: true)

      {"GET", "/.cratis/queries/ws"} ->
        hub(conn, app)

      {"GET", "/.cratis/queries/sse"} ->
        sse_hub(conn, app)

      {"POST", "/.cratis/queries/sse/subscribe"} ->
        sse_control(conn, app, :subscribe)

      {"POST", "/.cratis/queries/sse/unsubscribe"} ->
        sse_control(conn, app, :unsubscribe)

      {"GET", "/.cratis/event-model" <> _ = path} ->
        Cratis.Arc.Plug.EventModel.call(conn, app, state, path)

      _ ->
        conn
    end
  end

  defp hub(conn, app) do
    case Request.build(conn, app) do
      {:ok, conn, ctx} ->
        conn |> WebSockAdapter.upgrade(Cratis.Arc.Plug.Hub, %{app: app, ctx: ctx}, []) |> halt()

      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})
    end
  end

  defp sse_hub(conn, app) do
    case Request.build(conn, app) do
      {:ok, conn, ctx} ->
        conn |> Cratis.Arc.Plug.SseHub.stream(app, ctx) |> halt()

      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})
    end
  end

  defp sse_control(conn, app, kind) do
    case Request.build(conn, app) do
      {:ok, conn, ctx} ->
        case Cratis.Arc.Plug.read_json(conn, app) do
          {:ok, conn, %{} = body} -> Cratis.Arc.Plug.SseHub.control(conn, app, ctx, kind, body)
          {:ok, conn, _other} -> send_status(conn, 400)
          {:error, conn, _message} -> send_status(conn, 400)
        end

      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})
    end
  end

  defp catalog(conn, app, state, opts) do
    case state.config[:introspection] do
      false -> conn
      _mode -> authenticated_catalog(conn, app, state, opts)
    end
  end

  defp authenticated_catalog(conn, app, state, opts) do
    case Request.build(conn, app) do
      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})

      {:ok, conn, ctx} ->
        render_catalog(conn, ctx, state, opts)
    end
  end

  defp render_catalog(conn, ctx, state, opts) do
    if state.config[:introspection] == :authenticated and not ctx.principal.authenticated? do
      json(conn, 401, %{"message" => "Authentication is required."})
    else
      conn = if opts[:per_user], do: no_store(conn), else: conn
      builder = opts[:build]
      json(conn, 200, builder.(state, state.config))
    end
  end

  defp commands(state, config) do
    opts = route_opts(config)

    for d <- state.commands do
      %{
        "name" => d.name,
        "namespace" => d.namespace |> Enum.drop(config[:segments_to_skip]) |> Enum.join("."),
        "route" => Descriptor.command_route(d, opts),
        "type" => inspect(d.module),
        "documentationSummary" => d.doc || "",
        "payloadSchema" => schema(d.fields)
      }
    end
  end

  defp queries(state, config) do
    opts = route_opts(config)

    for d <- state.read_models, q <- d.queries do
      %{
        "name" => Cratis.Arc.Naming.pascal(q.name),
        "namespace" => d.namespace |> Enum.drop(config[:segments_to_skip]) |> Enum.join("."),
        "route" => Descriptor.query_route(d, q, opts),
        "type" => inspect(d.module),
        "fullyQualifiedName" => Descriptor.query_name(d, q),
        "documentationSummary" => q.doc || "",
        "argumentsSchema" => schema(q.params)
      }
    end
  end

  defp structure(state, config),
    do: Cratis.Arc.Structure.build(state.commands, state.read_models, config[:segments_to_skip])

  # The development availability routes exist only while the application allows overrides.
  defp development(conn, app, _state, serve) do
    if Cratis.Arc.Availability.Development.active?(app) and Cratis.Arc.Availability.enabled?(app),
      do: serve.(),
      else: conn
  end

  defp availability_model(app, state, _config) do
    definition = state.availability.definition

    %{
      "overrides" => Cratis.Arc.Availability.Development.current(app),
      "audiences" =>
        for(
          a <- definition.audiences,
          do: %{"name" => a["name"], "description" => a["description"], "source" => ""}
        ),
      "blocks" =>
        for(
          b <- definition.blocks,
          do: %{
            "name" => b["name"],
            "description" => b["description"],
            "source" => "",
            "alternatives" => []
          }
        ),
      "gates" => [],
      "contextValues" =>
        for(
          v <- definition.values,
          do: %{
            "name" => v.name,
            "type" => "",
            "origin" => inspect(v.provider),
            "required" => v.required
          }
        ),
      "personas" => []
    }
  end

  defp overrides(conn, app, state) do
    case Request.build(conn, app) do
      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})

      {:ok, conn, ctx} ->
        if state.config[:introspection] == :authenticated and not ctx.principal.authenticated? do
          json(conn, 401, %{"message" => "Authentication is required."})
        else
          apply_overrides(conn, app)
        end
    end
  end

  defp apply_overrides(conn, app) do
    case Cratis.Arc.Plug.read_json(conn, app) do
      {:ok, conn, %{} = body} ->
        {:ok, applied} = Cratis.Arc.Availability.Development.apply_overrides(app, body)
        json(conn, 200, applied)

      {:ok, conn, _other} ->
        send_status(conn, 400)

      {:error, conn, _message} ->
        send_status(conn, 400)
    end
  end

  defp route_opts(config),
    do: [route_prefix: config[:route_prefix], segments_to_skip: config[:segments_to_skip]]

  @doc false
  def schema(fields) do
    properties =
      Map.new(fields, fn f -> {Cratis.Arc.Naming.camel(f.name), type_schema(f.type)} end)

    required = for f <- fields, f.required?, do: Cratis.Arc.Naming.camel(f.name)
    %{"type" => "object", "properties" => properties, "required" => required}
  end

  @doc false
  def type_schema(:string), do: %{"type" => "string"}
  def type_schema(:integer), do: %{"type" => "integer"}
  def type_schema(:float), do: %{"type" => "number"}
  def type_schema(:boolean), do: %{"type" => "boolean"}
  def type_schema(:uuid), do: %{"type" => "string", "format" => "uuid"}
  def type_schema(:date), do: %{"type" => "string", "format" => "date"}
  def type_schema(:datetime), do: %{"type" => "string", "format" => "date-time"}
  def type_schema(:map), do: %{"type" => "object"}
  def type_schema({:list, inner}), do: %{"type" => "array", "items" => type_schema(inner)}

  def type_schema(module) when is_atom(module) do
    cond do
      Cratis.Arc.Types.concept?(module) -> type_schema(Cratis.Arc.Types.concept_primitive(module))
      Cratis.Arc.Types.schema?(module) -> schema(module.__arc_schema__())
      true -> %{}
    end
  end

  # The shape of the identity details, from the provider's declared details type.
  defp identity_schema(%{identity_provider: nil}, _config), do: %{}

  defp identity_schema(%{identity_provider: provider}, _config) do
    with true <- function_exported?(provider, :__arc_details__, 0),
         type when not is_nil(type) <- provider.__arc_details__(),
         true <- Cratis.Arc.Types.schema?(type) do
      schema(type.__arc_schema__())
    else
      _ -> %{}
    end
  end

  defp users(state, _config) do
    for provider <- state.users_providers,
        user <- provider.users(),
        do: Cratis.Arc.Identity.User.to_wire(user)
  end

  defp tenants(state, _config) do
    for provider <- state.tenants_providers,
        tenant <- provider.tenants(),
        do: %{"id" => tenant.id, "name" => tenant.name}
  end

  # `/.cratis/me` is registered only when an identity details provider exists. 401 and 403 carry
  # no body, and every response is private: it holds per-user data.
  defp identity(conn, app, state) do
    case state.identity_provider do
      nil ->
        conn

      _provider ->
        conn = no_store(conn)

        case Request.build(conn, app) do
          {:unauthenticated, conn} ->
            send_status(conn, 401)

          {:ok, conn, ctx} ->
            result = Cratis.Arc.Identity.resolve(app, ctx.principal, tenant: ctx.tenant)

            case Cratis.Arc.Identity.Result.status(result) do
              200 -> json(conn, 200, Cratis.Arc.Identity.Result.to_wire(result))
              status -> send_status(conn, status)
            end
        end
    end
  end

  defp no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store, private")
    |> put_resp_header("vary", "cookie")
  end

  defp send_status(conn, status), do: conn |> send_resp(status, "") |> halt()

  defp json(conn, status, body), do: Cratis.Arc.Plug.respond(conn, status, body)
end
