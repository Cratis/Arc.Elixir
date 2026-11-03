# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.Registration.RenameAuthor do
  @moduledoc "Renames an author. Only editors may."

  use Arc.Command

  authorize roles: ["editor"]

  schema do
    field :id, Library.Authors.AuthorId, key: true, required: true
    field :name, :string, required: true, min_length: 2, max_length: 50
  end

  def handle(%__MODULE__{name: name}, _ctx),
    do: {:append, %Library.Authors.AuthorRenamed{name: name}}
end
