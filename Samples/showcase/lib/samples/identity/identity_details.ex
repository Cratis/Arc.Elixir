# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Identity.IdentityDetails do
  @moduledoc "What the frontend knows about the signed-in user, beyond who they are."

  use Arc.Schema

  schema do
    field :display_name, :string, required: true
    field :tenant, :string, required: true
  end
end
