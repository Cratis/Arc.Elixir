# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.ChangeStream.ChangeStreamItem do
  @moduledoc "An item whose additions, replacements and removals reach the client as a change set."

  defstruct id: 0, label: "", value: 0
end
