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

defmodule Arc.Authentication.MicrosoftIdentityPlatform do
  @moduledoc """
  Authenticates from the Microsoft identity platform headers an ingress supplies:
  `x-ms-client-principal` (a base64 client principal), `x-ms-client-principal-id` and
  `x-ms-client-principal-name`. These are what Azure App Service, Container Apps, Cratis AuthProxy
  and the Lens browser extension send.

  The headers are **not signed** by default. The handler ignores them, and the request stays
  anonymous, unless the application sets `trust_forwarded_identity_headers: true`. Enable that only
  when every request reaches the application through an ingress that authenticates callers, strips
  caller-supplied identity headers and writes trusted replacements, and when nothing can reach the
  application directly. The setting applies to every route.

      config :my_app, MyApp.Arc,
        authentication: [Arc.Authentication.MicrosoftIdentityPlatform],
        trust_forwarded_identity_headers: true

  To have the ingress attest the headers, enable [signed forwarded identity](`Arc.Identity.SignedForwarding`):
  with it there is no unsigned fallback. To let a support person or an agent act as a user, enable
  [on-behalf forwarding](`Arc.Identity.OnBehalfOf`).

  ## The principal

  Without signing, all three headers must be present, otherwise the request is left to the next
  handler. The id is the decoded `x-ms-client-principal-id` (RFC 8187 `UTF-8''` form
  percent-decoded). The name is the principal's `userDetails`, falling back to
  `x-ms-client-principal-name`. Roles are `userRoles` plus claims of the role claim type
  `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`; `sub` and the name identifier come
  from the id header, replacing any in the payload. The identity provider the ingress authenticated with is kept as the claim
  `urn:cratis:arc:identity:provider`. A payload that is not a valid client principal fails the request with 401.
  """

  @behaviour Arc.Authentication

  require Logger

  alias Arc.Identity.{Forwarded, OnBehalfOf, SignedForwarding}

  @principal_header "x-ms-client-principal"
  @id_header "x-ms-client-principal-id"
  @name_header "x-ms-client-principal-name"

  @impl true
  def authenticate(conn) do
    app = conn.private[:arc_application]
    config = Arc.Application.state(app).config

    if get_in(config, [:forwarded_identity, :enabled]) == true,
      do: signed(conn, app, config),
      else: unsigned(conn, app, config)
  end

  defp signed(conn, app, config) do
    case SignedForwarding.authenticate(conn, app, config) do
      {:failed, reason} ->
        Logger.debug("Signed forwarded identity rejected: #{reason}")
        :failed

      other ->
        other
    end
  end

  defp unsigned(conn, app, config) do
    has_header = fn name -> Plug.Conn.get_req_header(conn, name) != [] end
    on_behalf? = OnBehalfOf.present?(has_header)
    rejection = if on_behalf?, do: OnBehalfOf.admit(config)

    cond do
      rejection != nil ->
        reject(rejection)

      config[:trust_forwarded_identity_headers] != true ->
        if forwarded_headers?(conn), do: warn_untrusted()
        :anonymous

      not (has_header.(@id_header) and has_header.(@name_header) and
               has_header.(@principal_header)) ->
        if on_behalf?, do: reject(OnBehalfOf.failure(:missing_represented_user)), else: :anonymous

      true ->
        build(conn, app, config, on_behalf?)
    end
  end

  defp build(conn, app, config, on_behalf?) do
    id = header(conn, @id_header)
    name = header(conn, @name_header)

    case Forwarded.read_principal(header(conn, @principal_header)) do
      :error ->
        message = "Not authenticated - invalid representation of ClientPrincipal"
        if on_behalf?, do: reject(message), else: :failed

      {:ok, client} ->
        client =
          if client.user_details in [nil, ""],
            do: %{client | user_details: name || ""},
            else: client

        principal = Forwarded.to_principal(client, id)

        if on_behalf?,
          do: attach_actor(conn, principal, app, config),
          else: {:authenticated, principal}
    end
  end

  defp attach_actor(conn, principal, app, config) do
    forward = %{
      principal: header(conn, @principal_header),
      principal_id: header(conn, @id_header),
      actor: header(conn, OnBehalfOf.actor_header()),
      assertion: header(conn, OnBehalfOf.assertion_header()),
      tenant: tenant(conn, config),
      method: conn.method,
      path: conn.request_path
    }

    case OnBehalfOf.attach(
           forward,
           principal,
           app,
           config,
           OnBehalfOf.signing_keys(config),
           System.os_time(:second)
         ) do
      {:ok, actor, _valid_until} -> {:authenticated, %{principal | actor: actor}}
      {:error, reason} -> reject(reason)
    end
  end

  defp tenant(conn, config) do
    case config[:tenant_header] do
      name when is_binary(name) and name != "" -> header(conn, name)
      _ -> nil
    end
  end

  defp header(conn, name) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp forwarded_headers?(conn) do
    Enum.any?(conn.req_headers, fn {name, _} ->
      String.starts_with?(name, "x-ms-client-principal")
    end)
  end

  # The first rejection in a process is a warning with its reason; later ones are debug, so a
  # caller sending forged headers cannot flood the logs.
  defp reject(reason) do
    if :persistent_term.get({__MODULE__, :rejected}, false) do
      Logger.debug("On-behalf forward rejected: #{reason}")
    else
      :persistent_term.put({__MODULE__, :rejected}, true)
      Logger.warning("On-behalf forward rejected: #{reason}")
    end

    :failed
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
