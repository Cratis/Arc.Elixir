# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.Connection do
  @moduledoc """
  A resolved connection: the driver topology to talk to and the database on it.
  """

  defstruct topology: nil, database: nil, key: nil

  @type t :: %__MODULE__{topology: pid(), database: String.t(), key: term()}
end
