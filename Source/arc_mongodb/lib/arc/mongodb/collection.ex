# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Collection do
  @moduledoc """
  A collection of one document type, in the database of one tenant.

  Build it with `Arc.MongoDB.collection/3`. It is a cheap value: it holds where to talk to (the
  driver topology and the database the tenant resolves to) and how documents are stored (the
  document module and the naming policy). Resolve it where the tenant is known, for example at
  the start of a command or query, and do not keep it beyond the request.
  """

  defstruct app: nil,
            tenant: nil,
            purpose: :runtime,
            topology: nil,
            connection: nil,
            database: nil,
            name: nil,
            document: nil,
            policy: nil

  @type t :: %__MODULE__{
          app: module(),
          tenant: String.t() | nil,
          purpose: :runtime | :schema,
          topology: pid(),
          connection: term(),
          database: String.t(),
          name: String.t(),
          document: module(),
          policy: module()
        }
end
