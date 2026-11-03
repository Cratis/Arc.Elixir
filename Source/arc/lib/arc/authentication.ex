# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Authentication do
  @moduledoc """
  Authentication handlers turn an incoming request into an `Arc.Principal`.

  Handlers run in the order configured on the application. The first handler that recognizes the
  request decides:

    * `{:authenticated, principal}` - the chain stops with that principal
    * `:failed` - terminal; later handlers do not run and the caller gets a generic 401
    * `:anonymous` - this handler did not recognize the request; the next one tries. Anonymous
      is the final outcome only when no handler recognized the request.

  Arc does not authenticate users itself. The default handler, `Arc.Authentication.FromAssigns`,
  reads a principal your own plug assigned, so `phx.gen.auth`, token plugs and reverse proxies
  keep working unchanged.
  """

  @callback authenticate(Plug.Conn.t()) ::
              {:authenticated, Arc.Principal.t()} | :failed | :anonymous

  @doc false
  @spec run([module()], Plug.Conn.t()) ::
          {:authenticated, Arc.Principal.t()} | :failed | :anonymous
  def run(handlers, conn) do
    Enum.reduce_while(handlers, :anonymous, fn handler, _acc ->
      case handler.authenticate(conn) do
        :anonymous -> {:cont, :anonymous}
        other -> {:halt, other}
      end
    end)
  end
end

defmodule Arc.Authentication.FromAssigns do
  @moduledoc """
  Reads the principal from `conn.assigns[:arc_principal]` (an `Arc.Principal`), or builds one from
  the signed-in user your own authentication assigned: `conn.assigns.current_scope.user` (the
  `phx.gen.auth` shape) or `conn.assigns.current_user`, a map with `:id` and optionally `:name`,
  `:email` and `:roles`.
  """

  @behaviour Arc.Authentication

  @impl true
  def authenticate(conn) do
    case conn.assigns do
      %{arc_principal: %Arc.Principal{} = principal} ->
        {:authenticated, principal}

      %{current_scope: %{user: %{id: id} = user}} ->
        {:authenticated,
         Arc.Principal.new(
           to_string(id),
           to_string(Map.get(user, :name, Map.get(user, :email, id))),
           roles: Map.get(user, :roles, [])
         )}

      %{current_user: %{id: id} = user} ->
        {:authenticated,
         Arc.Principal.new(to_string(id), to_string(Map.get(user, :name, id)),
           roles: Map.get(user, :roles, [])
         )}

      _ ->
        :anonymous
    end
  end
end
