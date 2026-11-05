# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.LiveFeed.LiveFeed do
  @moduledoc "A message in the live feed."

  defstruct author: "", text: "", posted_at: ~U[1970-01-01 00:00:00Z]
end
