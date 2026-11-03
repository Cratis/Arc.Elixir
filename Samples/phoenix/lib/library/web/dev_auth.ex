# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.DevAuth do
  @moduledoc """
  A demo sign-in so the sample can show authorization without a user database.

  `?as=ada&roles=editor` (or the `x-demo-user` and `x-demo-roles` headers) signs in, and the
  session remembers it for the LiveView page. A real application replaces this with its own
  authentication, for example `phx.gen.auth`; Arc only needs `conn.assigns.arc_principal`, or a
  `current_scope`/`current_user` your authentication already assigned.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = conn |> fetch_session() |> fetch_query_params()

    case identity(conn) do
      nil ->
        conn

      {name, roles} ->
        conn
        |> put_session("user", %{id: name, name: name, roles: roles})
        |> assign(:arc_principal, Arc.Principal.new(name, name, roles: roles))
    end
  end

  defp identity(conn) do
    name = conn.params["as"] || header(conn, "x-demo-user")
    roles = conn.params["roles"] || header(conn, "x-demo-roles") || ""

    if name,
      do: {name, roles |> String.split(",", trim: true) |> Enum.map(&String.trim/1)},
      else: session_identity(conn)
  end

  defp session_identity(conn) do
    case get_session(conn, "user") do
      %{id: id, roles: roles} -> {id, roles}
      _ -> nil
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end
end
