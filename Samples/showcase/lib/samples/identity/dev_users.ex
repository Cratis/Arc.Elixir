# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Identity.DevUsers do
  @moduledoc "The users a development tool such as Lens can sign in as. Not authentication."

  @behaviour Cratis.Arc.Identity.UsersProvider

  @impl true
  def users do
    [
      %Cratis.Arc.Identity.User{user_id: "demo-user", user_details: "Demo User", roles: ["User"]},
      %Cratis.Arc.Identity.User{
        user_id: "secure-user",
        user_details: "Secure User",
        roles: ["User", "CrossCuttingAuthorization"]
      }
    ]
  end
end
