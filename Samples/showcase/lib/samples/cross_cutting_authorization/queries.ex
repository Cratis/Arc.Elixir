# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.CrossCuttingAuthorization.Queries do
  @moduledoc "Queries that are protected by `Samples.CrossCuttingAuthorization.Filter`."

  use Arc.ReadModel,
    model: Samples.CrossCuttingAuthorization.CrossCuttingAuthorizationStatus,
    types: [checked_at: :datetime]

  alias Samples.CrossCuttingAuthorization.CrossCuttingAuthorizationStatus

  @doc "The current secured status."
  @query many: false
  def secured(_args, _ctx) do
    {:ok,
     %CrossCuttingAuthorizationStatus{
       message: "Query authorized and executed through a cross-cutting filter.",
       checked_at: DateTime.utc_now()
     }}
  end
end
