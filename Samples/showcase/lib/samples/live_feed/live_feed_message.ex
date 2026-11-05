# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.LiveFeed.LiveFeedMessage do
  @moduledoc "The message a poster gets back."

  use Arc.Schema

  schema do
    field :author, :string
    field :text, :string
    field :posted_at, :datetime, required: true
  end
end
