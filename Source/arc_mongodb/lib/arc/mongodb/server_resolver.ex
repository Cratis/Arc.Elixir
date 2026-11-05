# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ServerResolver do
  @moduledoc """
  Chooses the server (the connection string) every connection starts from.

  The default returns the configured `:server`. Replace it to read the address from somewhere
  else, for example a service registry. To place a *tenant* on a server of its own, use
  `Arc.MongoDB.ConnectionResolver`.
  """

  @callback resolve(options :: Arc.MongoDB.Options.t()) :: String.t()
end

defmodule Arc.MongoDB.ServerResolver.Default do
  @moduledoc false
  @behaviour Arc.MongoDB.ServerResolver

  @impl true
  def resolve(options), do: options.server
end
