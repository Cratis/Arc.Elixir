# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.Introspection do
  @moduledoc false

  # The `/.cratis/*` discovery, identity and hub routes.

  import Plug.Conn

  alias Arc.{Descriptor, Principal}
  alias Arc.Plug.Request

  def call(conn, app, state) do
    case {conn.method, conn.request_path} do
      {"GET", "/.cratis/commands"} -> catalog(conn, app, state, &commands/2)
      {"GET", "/.cratis/queries"} -> catalog(conn, app, state, &queries/2)
      {"GET", "/.cratis/me"} -> identity(conn, app, state)
      {"GET", "/.cratis/identity-details/schema"} -> json(conn, 200, %{})
      {"GET", "/.cratis/users"} -> json(conn, 200, [])
      {"GET", "/.cratis/tenants"} -> json(conn, 200, [])
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

  defp catalog(conn, app, state, builder) do
    case state.config[:introspection] do
      false ->
        conn

      mode ->
        case Request.build(conn, app) do
          {:unauthenticated, conn} ->
            json(conn, 401, %{"message" => "Authentication failed."})

          {:ok, conn, ctx} ->
            if mode == :authenticated and not ctx.principal.authenticated?,
              do: json(conn, 401, %{"message" => "Authentication is required."}),
              else: json(conn, 200, builder.(state, state.config))
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

  # `/.cratis/me` is registered only when an identity details provider is configured.
  defp identity(conn, app, state) do
    case state.config[:identity_details] do
      nil ->
        conn

      provider ->
        case Request.build(conn, app) do
          {:unauthenticated, conn} ->
            json(conn, 401, %{"message" => "Authentication failed."})

          {:ok, conn, %{principal: %Principal{authenticated?: false}}} ->
            json(conn, 401, %{"message" => "Authentication is required."})

          {:ok, conn, ctx} ->
            case provider.details(ctx.principal) do
              {:ok, details} ->
                json(conn, 200, %{
                  "id" => ctx.principal.id,
                  "name" => ctx.principal.name,
                  "isAuthenticated" => true,
                  "isAuthorized" => true,
                  "roles" => ctx.principal.roles,
                  "details" => Arc.Wire.encode(details)
                })

              :forbidden ->
                json(conn, 403, %{"isAuthenticated" => true, "isAuthorized" => false})
            end
        end
    end
  end

  defp json(conn, status, body), do: Arc.Plug.respond(conn, status, body)
end
