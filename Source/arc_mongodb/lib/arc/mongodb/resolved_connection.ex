# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ResolvedConnection do
  @moduledoc """
  What a `Arc.MongoDB.ConnectionResolver` answers: the parts of a connection it decides.

  Every part is optional; what is left `nil` stays as configured. `identity` is replaced as a
  whole, so a password from one resolver never ends up next to an access token from another.

    * `:connection_string` - replaces the configured `:server`
    * `:database` - replaces the database name, **including** the tenant naming
    * `:identity` - `%{user_name:, password:}` for SCRAM authentication against the connection
      string's `authSource`, else its database, else `admin`. `:access_token` (MONGODB-OIDC) is
      refused: the MongoDB driver for Elixir has no OIDC mechanism
    * `:expires_at` - when the answer stops being valid; it is used until one minute before
  """

  defstruct connection_string: nil, database: nil, schema: nil, identity: nil, expires_at: nil

  @type identity :: %{
          optional(:user_name) => String.t() | nil,
          optional(:password) => String.t() | nil,
          optional(:access_token) => String.t() | nil
        }

  @type t :: %__MODULE__{
          connection_string: String.t() | nil,
          database: String.t() | nil,
          schema: String.t() | nil,
          identity: identity() | nil,
          expires_at: DateTime.t() | nil
        }

  @doc "Answers nothing: everything stays as configured."
  @spec unchanged() :: t()
  def unchanged, do: %__MODULE__{}
end
