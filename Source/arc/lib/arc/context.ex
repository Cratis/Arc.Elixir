# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Context do
  @moduledoc """
  Request-scoped facts handed to every command, query, validator and policy.

  Arc has no dependency injection container. Handlers call `Repo`, context modules and
  `Chronicle` directly, and receive the caller's facts through this struct. The same values are
  set as `Logger` metadata while the artifact runs (`:arc_correlation_id`, `:arc_tenant`).

    * `:application` - the `Arc.Application` module running the artifact
    * `:principal` - the `Arc.Principal` of the caller
    * `:tenant` - the resolved tenant, or `nil`
    * `:correlation_id` / `:causation_id` - tracing identifiers (correlation is echoed on the response)
    * `:metadata` - free-form map; copied to the Chronicle append as causation properties
    * `:deadline` - monotonic millisecond deadline, or `nil`
    * `:provided` - values returned by the command's `provide/2`
    * `:allowed_severity` - the highest non-blocking validation severity the caller accepts
    * `:chronicle` - options passed to every `Chronicle.append/3` (for example `client:`)
  """

  alias Arc.Principal

  defstruct application: nil,
            principal: %Principal{},
            tenant: nil,
            correlation_id: nil,
            causation_id: nil,
            metadata: %{},
            deadline: nil,
            provided: %{},
            allowed_severity: -1,
            chronicle: []

  @type t :: %__MODULE__{
          application: module() | nil,
          principal: Principal.t(),
          tenant: String.t() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          metadata: map(),
          deadline: integer() | nil,
          provided: map(),
          allowed_severity: integer(),
          chronicle: keyword()
        }

  @doc "Builds a context, generating a correlation id when none is given."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    base = struct(__MODULE__, opts)
    %{base | correlation_id: base.correlation_id || new_correlation_id()}
  end

  @doc "Generates a canonical lowercase UUID v4 string."
  @spec new_correlation_id() :: String.t()
  def new_correlation_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)
    c = Bitwise.bor(Bitwise.band(c, 0x0FFF), 0x4000)
    d = Bitwise.bor(Bitwise.band(d, 0x3FFF), 0x8000)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end

  @doc "Whether the deadline, if any, has passed."
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{deadline: nil}), do: false

  def expired?(%__MODULE__{deadline: deadline}),
    do: System.monotonic_time(:millisecond) >= deadline
end
