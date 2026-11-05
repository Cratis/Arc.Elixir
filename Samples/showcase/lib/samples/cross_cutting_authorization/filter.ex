# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.CrossCuttingAuthorization.Filter do
  @moduledoc """
  Cross-cutting authorization for a whole namespace.

  Neither the command nor the query of `Samples.CrossCuttingAuthorization` says anything about who
  may run it. This filter, registered under `filters:` in `config/runtime.exs`, requires the role
  `CrossCuttingAuthorization` of every artifact in the namespace.
  """

  @behaviour Arc.Filter

  @protected ["Samples", "CrossCuttingAuthorization"]
  @required_role "CrossCuttingAuthorization"

  @impl true
  def on_command(ctx, %Arc.Descriptor{namespace: @protected}), do: check(ctx)
  def on_command(_ctx, _descriptor), do: :ok

  @impl true
  def on_query(ctx, %Arc.Descriptor{namespace: @protected}, _query), do: check(ctx)
  def on_query(_ctx, _descriptor, _query), do: :ok

  defp check(ctx) do
    if @required_role in ctx.principal.roles,
      do: :ok,
      else:
        {:unauthorized,
         "Role '#{@required_role}' is required for artifacts in namespace '#{Enum.join(@protected, ".")}'."}
  end
end
