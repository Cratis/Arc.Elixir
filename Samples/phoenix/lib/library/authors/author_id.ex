# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.AuthorId do
  @moduledoc "Identifies an author. A strongly typed UUID, and the event source of every author event."

  use Chronicle.Concept, type: :uuid, event_source_id: true
end
