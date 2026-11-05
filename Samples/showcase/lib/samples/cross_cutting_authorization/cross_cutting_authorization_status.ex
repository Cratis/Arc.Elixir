# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.CrossCuttingAuthorization.CrossCuttingAuthorizationStatus do
  @moduledoc "A status message and when it was produced."

  defstruct message: "", checked_at: ~U[1970-01-01 00:00:00Z]
end
