# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.HealthController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  def show(conn, _params), do: json(conn, %{status: "ok"})
end
