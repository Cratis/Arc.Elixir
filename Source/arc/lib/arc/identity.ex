# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Identity.Context do
  @moduledoc """
  The input of an identity details provider: the authenticated caller.

    * `:id` - the identity identifier from the identity provider, `"unknown"` when absent
    * `:name` - the display name
    * `:claims` - `{type, value}` string pairs from the authenticated principal, including a
      `{"role", role}` pair per role
    * `:principal` - the full `Arc.Principal`
  """

  @enforce_keys [:id, :name]
  defstruct [:id, :name, :principal, claims: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          claims: [{String.t(), String.t()}],
          principal: Arc.Principal.t() | nil
        }
end

defmodule Arc.Identity.Details do
  @moduledoc """
  The result of an identity details provider, when it needs more than `{:ok, details}`:
  whether the user may enter the application at all, and the details to show.
  """

  defstruct authorized?: true, details: %{}

  @type t :: %__MODULE__{authorized?: boolean(), details: term()}
end

defmodule Arc.Identity.Result do
  @moduledoc """
  The resolved identity, as served from `/.cratis/me`.
  """

  defstruct id: nil, name: nil, roles: [], details: %{}, authenticated?: false, authorized?: false

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          roles: [String.t()],
          details: term(),
          authenticated?: boolean(),
          authorized?: boolean()
        }

  @doc "The result for a caller who is not signed in."
  @spec unauthenticated() :: t()
  def unauthenticated, do: %__MODULE__{}

  @doc "The HTTP status the identity contract maps this result to."
  @spec status(t()) :: 200 | 401 | 403
  def status(%__MODULE__{authenticated?: false}), do: 401
  def status(%__MODULE__{authorized?: false}), do: 403
  def status(%__MODULE__{}), do: 200

  @doc "Converts the result to the `/.cratis/me` body."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = result) do
    %{
      "id" => result.id,
      "name" => result.name,
      "isAuthenticated" => result.authenticated?,
      "isAuthorized" => result.authorized?,
      "roles" => result.roles,
      "details" => Arc.Wire.encode(result.details)
    }
  end
end

defmodule Arc.Identity.Provider do
  @moduledoc """
  Supplies the application-specific details of the signed-in user.

  `details/1` runs on every identity request, with a fresh `Arc.Identity.Context`. Cache expensive
  lookups inside it. It may return:

    * `{:ok, details}` - the user may enter; `details` is a map or an `Arc.Schema` struct
    * `{:unauthorized, details}` - the user is authenticated but may not use the application (403)
    * an `Arc.Identity.Details` struct, equivalent to the above

  Use `use Arc.Identity.Provider, details: MyApp.Details` to declare the details type; Arc
  discovers the provider from its application modules. At most one provider may exist per
  application, or name one explicitly with the `identity_details:` option.
  """

  @callback details(Arc.Identity.Context.t()) ::
              {:ok, term()} | {:unauthorized, term()} | Arc.Identity.Details.t()

  @doc false
  defmacro __using__(opts) do
    details = Keyword.get(opts, :details)

    quote do
      @behaviour Arc.Identity.Provider
      def __arc_details__, do: unquote(details)
    end
  end
end

defmodule Arc.Identity.User do
  @moduledoc """
  A development user, as listed by `/.cratis/users` for tools such as Lens.

  The wire shape matches the other Arc implementations: a `microsoftIdentity` client principal
  and application `details`.
  """

  defstruct identity_provider: "dev",
            user_id: nil,
            user_details: nil,
            roles: [],
            claims: [],
            details: %{}

  @type t :: %__MODULE__{
          identity_provider: String.t(),
          user_id: String.t(),
          user_details: String.t(),
          roles: [String.t()],
          claims: [{String.t(), String.t()}],
          details: term()
        }

  @doc false
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = user) do
    %{
      "microsoftIdentity" => %{
        "identityProvider" => user.identity_provider,
        "userId" => user.user_id,
        "userDetails" => user.user_details,
        "userRoles" => user.roles,
        "claims" =>
          Enum.map(user.claims, fn {type, value} -> %{"typ" => type, "val" => value} end)
      },
      "details" => Arc.Wire.encode(user.details)
    }
  end
end

defmodule Arc.Identity.Tenant do
  @moduledoc "A development tenant, as listed by `/.cratis/tenants`."

  @enforce_keys [:id, :name]
  defstruct [:id, :name]

  @type t :: %__MODULE__{id: String.t(), name: String.t()}
end

defmodule Arc.Identity.UsersProvider do
  @moduledoc """
  Lists the development users a tool such as Lens offers to sign in as.

  Implement it in a development-only module; Arc discovers it. It is not authentication:
  a user list is not proof of identity or membership.
  """

  @callback users() :: [Arc.Identity.User.t()]
end

defmodule Arc.Identity.TenantsProvider do
  @moduledoc """
  Lists the tenants a tool such as Lens offers to select.

  This is a development seam, unrelated to how a request's tenant is resolved.
  """

  @callback tenants() :: [Arc.Identity.Tenant.t()]
end

defmodule Arc.Identity do
  @moduledoc """
  The identity the frontend shows: who the caller is, their roles, and application-specific details.

  Authentication establishes an `Arc.Principal`; identity enrichment turns it into what the UI
  needs. The two are separate on purpose: identity is presentation data and **never** an
  authorization decision. Commands and queries are protected by `authorize`, not by what this
  module returns.

  The frontend reads it from `GET /.cratis/me`; LiveView reads it with
  `Arc.LiveView.assign_identity/2`. Both call `resolve/2`, so they cannot disagree.

  ## Providing details

  Implement `Arc.Identity.Provider` and Arc discovers it:

      defmodule MyApp.IdentityDetails do
        use Arc.Identity.Provider, details: MyApp.Identity.Details

        @impl true
        def details(%Arc.Identity.Context{id: id}) do
          {:ok, %MyApp.Identity.Details{display_name: MyApp.Accounts.display_name(id)}}
        end
      end

  `details:` names an `Arc.Schema` module. It is what `/.cratis/identity-details/schema` describes
  and what proxy generation turns into a typed TypeScript class for `useIdentity`.

  ## The three outcomes

    * not authenticated - `GET /.cratis/me` answers 401
    * authenticated but the provider returned `{:unauthorized, details}` - 403
    * otherwise - 200 with `{id, name, isAuthenticated, isAuthorized, roles, details}`
  """

  alias Arc.Identity.{Context, Result}
  alias Arc.Principal

  @doc """
  Resolves the identity of `principal` by running the application's identity provider.

  Returns an `Arc.Identity.Result`. With no provider configured the details are an empty map.
  """
  @spec resolve(module(), Principal.t()) :: Result.t()
  def resolve(_application, %Principal{authenticated?: false}), do: Result.unauthenticated()

  def resolve(application, %Principal{} = principal) do
    context = %Context{
      id: principal.id || "unknown",
      name: principal.name || "",
      claims: claims(principal),
      principal: principal
    }

    {authorized?, details} =
      case provider(application) do
        nil -> {true, %{}}
        provider -> normalize(provider.details(context))
      end

    %Result{
      id: context.id,
      name: context.name,
      roles: principal.roles,
      details: details,
      authenticated?: true,
      authorized?: authorized?
    }
  end

  @doc "The identity provider module of `application`, or `nil`."
  @spec provider(module()) :: module() | nil
  def provider(application), do: Arc.Application.state(application).identity_provider

  defp normalize({:ok, details}), do: {true, details}
  defp normalize({:unauthorized, details}), do: {false, details}

  defp normalize(%Arc.Identity.Details{authorized?: authorized?, details: details}),
    do: {authorized?, details}

  defp claims(%Principal{} = principal) do
    claim_pairs =
      Enum.map(principal.claims, fn {type, value} -> {to_string(type), claim_value(value)} end)

    role_pairs = Enum.map(principal.roles, &{"role", &1})
    claim_pairs ++ role_pairs
  end

  defp claim_value(value) when is_binary(value), do: value
  defp claim_value(value), do: to_string(value)
end
