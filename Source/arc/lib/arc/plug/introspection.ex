# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.Introspection do
  @moduledoc false

  # The `/.cratis/*` discovery, identity and hub routes.

  import Plug.Conn

  alias Arc.Descriptor
  alias Arc.Plug.Request

  def call(conn, app, state) do
    case {conn.method, conn.request_path} do
      {"GET", "/.cratis/commands"} -> catalog(conn, app, state, &commands/2)
      {"GET", "/.cratis/queries"} -> catalog(conn, app, state, &queries/2)
      {"GET", "/.cratis/me"} -> identity(conn, app, state)
      {"GET", "/.cratis/identity-details/schema"} -> catalog(conn, app, state, &identity_schema/2)
      {"GET", "/.cratis/users"} -> catalog(conn, app, state, &users/2, per_user: true)
      {"GET", "/.cratis/tenants"} -> catalog(conn, app, state, &tenants/2, per_user: true)
      {"GET", "/.cratis/queries/ws"} -> hub(conn, app)
      _ -> conn
    end
  end

  defp hub(conn, app) do
    case Request.build(conn, app) do
      {:ok, conn, ctx} ->
        conn |> WebSockAdapter.upgrade(Arc.Plug.Hub, %{app: app, ctx: ctx}, []) |> halt()

      {:unauthenticated, conn} ->
        json(conn, 401, %{"message" => "Authentication failed."})
    end
  end

  defp catalog(conn, app, state, builder, opts \\ []) do
    case state.config[:introspection] do
      false ->
        conn

      mode ->
        case Request.build(conn, app) do
          {:unauthenticated, conn} ->
            json(conn, 401, %{"message" => "Authentication failed."})

          {:ok, conn, ctx} ->
            if mode == :authenticated and not ctx.principal.authenticated? do
              json(conn, 401, %{"message" => "Authentication is required."})
            else
              conn = if opts[:per_user], do: no_store(conn), else: conn
              json(conn, 200, builder.(state, state.config))
            end
        end
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
        "name" => Arc.Naming.pascal(q.name),
        "namespace" => d.namespace |> Enum.drop(config[:segments_to_skip]) |> Enum.join("."),
        "route" => Descriptor.query_route(d, q, opts),
        "type" => inspect(d.module),
        "fullyQualifiedName" => Descriptor.query_name(d, q),
        "documentationSummary" => q.doc || "",
        "argumentsSchema" => schema(q.params)
      }
    end
  end

  defp route_opts(config),
    do: [route_prefix: config[:route_prefix], segments_to_skip: config[:segments_to_skip]]

  defp schema(fields) do
    properties = Map.new(fields, fn f -> {Arc.Naming.camel(f.name), type_schema(f.type)} end)
    required = for f <- fields, f.required?, do: Arc.Naming.camel(f.name)
    %{"type" => "object", "properties" => properties, "required" => required}
  end

  defp type_schema(:string), do: %{"type" => "string"}
  defp type_schema(:integer), do: %{"type" => "integer"}
  defp type_schema(:float), do: %{"type" => "number"}
  defp type_schema(:boolean), do: %{"type" => "boolean"}
  defp type_schema(:uuid), do: %{"type" => "string", "format" => "uuid"}
  defp type_schema(:date), do: %{"type" => "string", "format" => "date"}
  defp type_schema(:datetime), do: %{"type" => "string", "format" => "date-time"}
  defp type_schema(:map), do: %{"type" => "object"}
  defp type_schema({:list, inner}), do: %{"type" => "array", "items" => type_schema(inner)}

  defp type_schema(module) when is_atom(module) do
    cond do
      Arc.Types.concept?(module) -> type_schema(Arc.Types.concept_primitive(module))
      Arc.Types.schema?(module) -> schema(module.__arc_schema__())
      true -> %{}
    end
  end

  # The shape of the identity details, from the provider's declared details type.
  defp identity_schema(%{identity_provider: nil}, _config), do: %{}

  defp identity_schema(%{identity_provider: provider}, _config) do
    with true <- function_exported?(provider, :__arc_details__, 0),
         type when not is_nil(type) <- provider.__arc_details__(),
         true <- Arc.Types.schema?(type) do
      schema(type.__arc_schema__())
    else
      _ -> %{}
    end
  end

  defp users(state, _config) do
    for provider <- state.users_providers,
        user <- provider.users(),
        do: Arc.Identity.User.to_wire(user)
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
            result = Arc.Identity.resolve(app, ctx.principal)

            case Arc.Identity.Result.status(result) do
              200 -> json(conn, 200, Arc.Identity.Result.to_wire(result))
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

  defp json(conn, status, body), do: Arc.Plug.respond(conn, status, body)
end
