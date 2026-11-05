# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Web.CookieIdentity do
  @moduledoc """
  Turns the demo's sign-in and tenant **cookies** into the headers Arc reads.

  A WebSocket handshake and an `EventSource` can send cookies but not custom headers, so the
  browser keeps the sign-in (`x-ms-client-principal`, the base64 client principal JSON) and the
  selected tenant (`x-cratis-tenant-id`) in cookies as well. An explicit header wins over a cookie.

  In a real application an ingress or a session plug does this, and nothing the client can set
  freely is trusted as an identity.
  """

  @behaviour Plug

  import Plug.Conn

  @principal "x-ms-client-principal"
  @id "x-ms-client-principal-id"
  @name "x-ms-client-principal-name"
  @tenant "x-cratis-tenant-id"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    conn
    |> from_cookie(@principal)
    |> identity_headers()
    |> from_cookie(@tenant)
  end

  defp from_cookie(conn, name) do
    case {get_req_header(conn, name), conn.req_cookies[name]} do
      {[], value} when is_binary(value) and value != "" -> put_req_header(conn, name, value)
      _ -> conn
    end
  end

  # The id and name headers come from the principal itself.
  defp identity_headers(conn) do
    with [principal] <- get_req_header(conn, @principal),
         {:ok, json} <- Base.decode64(principal),
         {:ok, %{"userId" => id, "userDetails" => name}} <- Jason.decode(json) do
      conn
      |> put_new_header(@id, id)
      |> put_new_header(@name, name)
    else
      _ -> conn
    end
  end

  defp put_new_header(conn, name, value) do
    if get_req_header(conn, name) == [], do: put_req_header(conn, name, value), else: conn
  end
end
