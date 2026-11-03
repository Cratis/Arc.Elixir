# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Identity.DevUsers do
  @moduledoc "The users a development tool such as Lens can sign in as. Not authentication."

  @behaviour Arc.Identity.UsersProvider

  @impl true
  def users do
    [
      %Arc.Identity.User{user_id: "ada", user_details: "ada", roles: []},
      %Arc.Identity.User{user_id: "ed", user_details: "ed", roles: ["editor"]}
    ]
  end
end
