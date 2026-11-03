# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Counters.CounterId do
  @moduledoc "Identifies a counter; the event source of its events."

  use Chronicle.Concept, type: :uuid, event_source_id: true
end
