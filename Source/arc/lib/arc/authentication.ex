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

defmodule Arc.Authentication.ClientPrincipal do
  @moduledoc """
  Authenticates from the Microsoft identity platform headers an ingress supplies:
  `x-ms-client-principal` (a base64 client principal), `x-ms-client-principal-id` and
  `x-ms-client-principal-name`. These are what Azure App Service, Container Apps, Cratis AuthProxy
  and the Lens browser extension send.

  The headers are **not signed**. The handler ignores them, and the request stays anonymous, unless the
  application sets `trust_forwarded_identity_headers: true`. Enable that only when every request
  reaches the application through an ingress that authenticates callers, strips caller-supplied
  identity headers and writes trusted replacements, and when nothing can reach the application
  directly. The setting applies to every route.

      config :my_app, MyApp.Arc,
        authentication: [Arc.Authentication.ClientPrincipal],
        trust_forwarded_identity_headers: true

  The principal gets its id from `x-ms-client-principal-id` (percent-decoded when it uses the
  RFC 8187 `UTF-8''` form), else the `sub` claim, else the principal's `userId`, else `"unknown"`;
  its name from `x-ms-client-principal-name`, else the principal's `userDetails`. Roles come from
  `userRoles` and role claims. The identity provider the ingress authenticated with is kept as the
  claim `"urn:cratis:arc:identity:provider"`. A payload that is not valid base64 JSON fails the
  request with 401.
  """

  @behaviour Arc.Authentication

  require Logger

  @identity_provider_claim "urn:cratis:arc:identity:provider"
  @role_claims ["role", "roles", "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"]
  @name_id_claims ["sub", "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]

  @impl true
  def authenticate(conn) do
    application = conn.private[:arc_application]
    principal = header(conn, "x-ms-client-principal")
    id = header(conn, "x-ms-client-principal-id")
    name = header(conn, "x-ms-client-principal-name")

    cond do
      principal == nil and id == nil -> :anonymous
      not trusted?(application) -> warn_untrusted() |> then(fn _ -> :anonymous end)
      true -> build(principal, id, name)
    end
  end

  @doc "The application to read the trust setting from, recorded by `Arc.Plug` on the connection."
  @spec put_application(Plug.Conn.t(), module()) :: Plug.Conn.t()
  def put_application(conn, application),
    do: Plug.Conn.put_private(conn, :arc_application, application)

  defp trusted?(nil), do: false

  defp trusted?(application),
    do: Arc.Application.state(application).config[:trust_forwarded_identity_headers] == true

  defp build(payload, id, name) do
    with {:ok, parsed} <- parse(payload) do
      claims =
        Map.new(parsed["claims"] || [], fn %{"typ" => type, "val" => value} -> {type, value} end)

      roles =
        (parsed["userRoles"] || []) ++
          for({type, value} <- claims, type in @role_claims, do: value)

      claims = Map.put(claims, @identity_provider_claim, parsed["identityProvider"] || "")

      principal_id =
        decode_id(id) || Enum.find_value(@name_id_claims, &Map.get(claims, &1)) ||
          parsed["userId"] || "unknown"

      principal_name = name || parsed["userDetails"] || ""

      {:authenticated,
       Arc.Principal.new(principal_id, principal_name, roles: Enum.uniq(roles), claims: claims)}
    else
      :error -> :failed
    end
  end

  defp parse(nil), do: {:ok, %{}}

  defp parse(payload) do
    with {:ok, json} <-
           Base.decode64(payload, padding: false, ignore: :whitespace) |> or_padded(payload),
         {:ok, %{} = parsed} <- Jason.decode(json) do
      {:ok, parsed}
    else
      _ -> :error
    end
  end

  defp or_padded({:ok, _} = ok, _payload), do: ok
  defp or_padded(:error, payload), do: Base.decode64(payload, ignore: :whitespace)

  defp decode_id(nil), do: nil
  defp decode_id("UTF-8''" <> encoded), do: URI.decode(encoded)
  defp decode_id(id), do: id

  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] when value != "" -> value
      _ -> nil
    end
  end

  defp warn_untrusted do
    unless :persistent_term.get({__MODULE__, :warned}, false) do
      :persistent_term.put({__MODULE__, :warned}, true)

      Logger.warning(
        "A request carried x-ms-client-principal headers but trust_forwarded_identity_headers is not enabled, so they were ignored. " <>
          "Enable it only behind an ingress that authenticates callers and strips client-supplied identity headers."
      )
    end

    :ok
  end
end
