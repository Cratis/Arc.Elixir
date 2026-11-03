# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Principal do
  @moduledoc """
  The authenticated caller of a command or query.

  Built by an `Arc.Authentication` handler from whatever your application already uses to
  authenticate (`phx.gen.auth`, a token plug, a reverse proxy). Arc never invents a second
  authentication system.
  """

  defstruct id: nil, name: nil, authenticated?: false, roles: [], claims: %{}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t() | nil,
          authenticated?: boolean(),
          roles: [String.t()],
          claims: %{optional(String.t()) => term()}
        }

  @doc "The anonymous principal."
  @spec anonymous() :: t()
  def anonymous, do: %__MODULE__{}

  @doc "Builds an authenticated principal."
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(id, name, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      authenticated?: true,
      roles: Keyword.get(opts, :roles, []),
      claims: Keyword.get(opts, :claims, %{})
    }
  end

  @doc "Whether the principal has at least one of the given roles."
  @spec in_any_role?(t(), [String.t()]) :: boolean()
  def in_any_role?(%__MODULE__{roles: roles}, wanted), do: Enum.any?(wanted, &(&1 in roles))
end
