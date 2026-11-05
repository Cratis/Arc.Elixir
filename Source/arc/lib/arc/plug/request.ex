# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Plug.Request do
  @moduledoc false

  # Builds the Arc context for an HTTP request or a WebSocket handshake: correlation, tenant,
  # severity tolerance and the authenticated principal.

  import Plug.Conn

  alias Arc.{Authentication, Context, Principal}

  @uuid ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
  @max_allowed_severity 2

  @spec build(Plug.Conn.t(), module()) ::
          {:ok, Plug.Conn.t(), Context.t()} | {:unauthenticated, Plug.Conn.t()}
  def build(conn, app) do
    config = Arc.Application.state(app).config
    correlation = correlation_id(conn, config[:correlation_header])
    conn = put_resp_header(conn, config[:correlation_header], correlation)

    conn = Plug.Conn.put_private(conn, :arc_application, app)

    case Authentication.run(config[:authentication], conn) do
      :failed ->
        {:unauthenticated, conn}

      auth ->
        principal =
          case auth do
            {:authenticated, %Principal{} = p} -> p
            :anonymous -> Principal.anonymous()
          end

        ctx =
          Arc.context(app,
            principal: principal,
            tenant: Arc.Tenancy.resolve(conn, principal, config),
            correlation_id: correlation,
            allowed_severity: allowed_severity(conn)
          )

        {:ok, conn, ctx}
    end
  end

  defp correlation_id(conn, header) do
    case first_header(conn, header) do
      nil ->
        Context.new_correlation_id()

      value ->
        if Regex.match?(@uuid, value),
          do: String.downcase(value),
          else: Context.new_correlation_id()
    end
  end

  defp allowed_severity(conn) do
    with value when is_binary(value) <- first_header(conn, "x-allowed-severity"),
         {n, ""} <- Integer.parse(value),
         true <- n in 0..3 do
      min(n, @max_allowed_severity)
    else
      _ -> -1
    end
  end

  defp first_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end
end
