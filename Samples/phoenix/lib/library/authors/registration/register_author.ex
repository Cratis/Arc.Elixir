# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.Registration.RegisterAuthor do
  @moduledoc "Registers a new author."

  use Arc.Command

  schema do
    field(:id, Library.Authors.AuthorId, key: true, required: true)
    field(:name, :string, required: true, min_length: 2, max_length: 50)
  end

  # A cross-field rule beyond the declarative ones above.
  def validate(%__MODULE__{name: name}, _ctx) when name in ["admin", "root"],
    do: {:error, Arc.Validation.error("That name is reserved.", [:name])}

  def validate(_command, _ctx), do: :ok

  # Decide, and return what happened. Arc appends the event to the command's key.
  def handle(%__MODULE__{name: name}, _ctx),
    do: {:append, %Library.Authors.AuthorRegistered{name: name}}
end
