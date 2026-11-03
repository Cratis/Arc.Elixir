# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Identity.Provider do
  @moduledoc """
  Supplies the identity details. This is presentation data for the UI: whether the rename button
  shows. Renaming itself is protected by `authorize roles: ["editor"]` on the command.
  """

  use Arc.Identity.Provider, details: Library.Identity.IdentityDetails

  @impl true
  def details(%Arc.Identity.Context{name: name, principal: principal}) do
    {:ok,
     %Library.Identity.IdentityDetails{
       display_name: "Hello, #{name}",
       can_rename: "editor" in principal.roles
     }}
  end
end
