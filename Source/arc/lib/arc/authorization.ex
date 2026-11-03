# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Authorization do
  @moduledoc """
  Authorization declarations and checks for commands and queries.

  Declare requirements on the artifact:

      authorize roles: ["admin"]      # at least one role
      authorize :authenticated        # any signed-in caller
      authorize policy: :can_publish  # a named `Arc.Policy`
      allow_anonymous()

  With no declaration an artifact is open. A query declaration (`@query authorize: [...]`)
  replaces the module-level declaration for that query.
  """

  alias Arc.{Context, Principal}

  @type requirement :: %{
          roles: [String.t()],
          policy: atom() | nil,
          allow_anonymous: boolean(),
          authenticated?: boolean()
        }

  @doc "An empty requirement."
  @spec open() :: requirement()
  def open, do: %{roles: [], policy: nil, allow_anonymous: false, authenticated?: false}

  @doc false
  @spec normalize(keyword() | atom() | nil) :: requirement()
  def normalize(nil), do: open()
  def normalize(:authenticated), do: %{open() | authenticated?: true}

  def normalize(opts) when is_list(opts) do
    roles = Keyword.get(opts, :roles, [])

    %{
      open()
      | roles: roles,
        policy: Keyword.get(opts, :policy),
        authenticated?:
          Keyword.get(opts, :authenticated, false) or roles != [] or
            Keyword.has_key?(opts, :policy),
        allow_anonymous: Keyword.get(opts, :allow_anonymous, false)
    }
  end

  @doc """
  Checks a requirement against the caller. Returns `:ok`, `{:error, :unauthenticated}` or
  `{:error, {:forbidden, reason}}`.
  """
  @spec check(requirement(), Context.t(), term()) ::
          :ok | {:error, :unauthenticated | {:forbidden, String.t()}}
  def check(%{allow_anonymous: true}, _ctx, _subject), do: :ok

  def check(req, %Context{principal: %Principal{} = principal} = ctx, subject) do
    cond do
      req.authenticated? and not principal.authenticated? ->
        {:error, :unauthenticated}

      req.roles != [] and not Principal.in_any_role?(principal, req.roles) ->
        {:error, {:forbidden, "Requires one of the roles: #{Enum.join(req.roles, ", ")}."}}

      req.policy != nil ->
        check_policy(req.policy, ctx, subject)

      true ->
        :ok
    end
  end

  defp check_policy(name, ctx, subject) do
    case Arc.Application.policy(ctx.application, name) do
      nil ->
        {:error, {:forbidden, "Unknown policy #{inspect(name)}."}}

      policy ->
        if policy.authorize?(ctx, subject),
          do: :ok,
          else: {:error, {:forbidden, "Policy #{inspect(name)} denied the request."}}
    end
  end
end

defmodule Arc.Policy do
  @moduledoc """
  A named authorization policy. Register it on the application with `policies: [can_publish: MyApp.Policies.CanPublish]`.
  """

  @callback authorize?(Arc.Context.t(), subject :: term()) :: boolean()
end
