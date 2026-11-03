# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ArcFixtures.Authors.AuthorId do
  use Chronicle.Concept, type: :uuid, event_source_id: true
end

defmodule ArcFixtures.Authors.AuthorRegistered do
  use Chronicle.Events.EventType, id: "arc-fixture-author-registered"
  defstruct name: ""
end

defmodule ArcFixtures.Authors.Author do
  defstruct id: "", name: "", registered: 0
end

defmodule ArcFixtures.Authors.AuthorReducer do
  use Chronicle.Reducers.Reducer, model: ArcFixtures.Authors.Author

  @handles ArcFixtures.Authors.AuthorRegistered

  @impl true
  def reduce(%ArcFixtures.Authors.AuthorRegistered{} = event, model, context) do
    %ArcFixtures.Authors.Author{
      model
      | id: context.event_source_id,
        name: event.name,
        registered: model.registered + 1
    }
  end
end

defmodule ArcFixtures.Authors.Registration.RegisterAuthor do
  @moduledoc "Registers a new author."
  use Arc.Command

  schema do
    field(:id, ArcFixtures.Authors.AuthorId,
      key: true,
      required: true,
      doc: "Identifies the author."
    )

    field(:name, :string, required: true, max_length: 10)
    field(:email, :string, email: true)
    field(:age, :integer, min: 0, max: 150)
    field(:tags, {:list, :string})
  end

  def validate(%__MODULE__{name: "forbidden"}, _ctx),
    do: {:error, Arc.Validation.error("That name is not allowed.", [:name])}

  def validate(_command, _ctx), do: :ok

  def handle(%__MODULE__{} = command, _ctx),
    do: {:append, %ArcFixtures.Authors.AuthorRegistered{name: command.name}}
end

defmodule ArcFixtures.Authors.Registration.RenameAuthor do
  @moduledoc "Renames an author; only admins may."
  use Arc.Command
  authorize(roles: ["admin"])
  response(:string)

  schema do
    field(:id, :uuid, key: true, required: true)
    field(:name, :string, required: true)
  end

  def provide(%__MODULE__{id: id}, _ctx), do: {:ok, %{old_name: "previous-" <> id}}

  def handle(%__MODULE__{} = command, ctx),
    do:
      {:append, %ArcFixtures.Authors.AuthorRegistered{name: command.name}, ctx.provided.old_name}
end

defmodule ArcFixtures.Authors.Registration.Explode do
  @moduledoc false
  use Arc.Command
  allow_anonymous()

  schema do
    field(:id, :uuid, key: true)
  end

  def handle(_command, _ctx), do: raise("boom")
end

defmodule ArcFixtures.Authors.Listing.Authors do
  @moduledoc "Queries over authors."
  use Arc.ReadModel, model: ArcFixtures.Authors.Author

  @doc "All authors."
  @query many: true
  def all_authors(_args, _ctx), do: {:ok, ArcFixtures.Store.all()}

  @query params: [id: :uuid], many: false
  def by_id(%{id: id}, _ctx), do: {:ok, Enum.find(ArcFixtures.Store.all(), &(&1.id == id))}

  @query many: true, authorize: [roles: ["admin"]]
  def secret_authors(_args, _ctx), do: {:ok, []}

  @observe many: true, topics: ["authors"]
  def live_authors(_args, _ctx), do: {:ok, ArcFixtures.Store.all()}
end

defmodule ArcFixtures.Store do
  @moduledoc false
  def start, do: :persistent_term.put(__MODULE__, [])
  def all, do: :persistent_term.get(__MODULE__, [])
  def put(list), do: :persistent_term.put(__MODULE__, list)
end

defmodule ArcFixtures.App do
  use Arc.Application,
    otp_app: :cratis_arc,
    artifacts: [
      ArcFixtures.Authors.Registration.RegisterAuthor,
      ArcFixtures.Authors.Registration.RenameAuthor,
      ArcFixtures.Authors.Registration.Explode,
      ArcFixtures.Authors.Listing.Authors
    ]
end
