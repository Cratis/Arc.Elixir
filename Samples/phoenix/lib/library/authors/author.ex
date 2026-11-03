# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.Author do
  @moduledoc "An author as the application shows it. Chronicle keeps it current from the events."

  use Chronicle.ReadModels.ReadModel

  defstruct id: "", name: ""

  from(Library.Authors.AuthorRegistered, set: [id: :event_source_id, name: :name])
  from(Library.Authors.AuthorRenamed, set: [name: :name])
end
