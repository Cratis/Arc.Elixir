# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.CrossCuttingAuthorization.RunSecuredCommand do
  @moduledoc "A command in the protected namespace: the filter decides who may run it."

  use Arc.Command
  response :string

  schema do
    field :message, :string, required: true
  end

  def handle(%__MODULE__{message: message}, _ctx) do
    time = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    {:ok, "Command authorized and executed at #{time} — #{message}"}
  end
end
