# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.AuthorRegistered do
  @moduledoc "An author was registered."

  use Chronicle.Events.EventType, id: "library-author-registered"

  defstruct name: ""

  # A store-level rule: no two authors may share a name. Chronicle enforces it at append time,
  # and Arc reports a violation to the client as a `constraintViolation` validation result.
  unique(:name, message: "An author with that name is already registered.")
end
