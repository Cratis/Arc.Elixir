# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Identity.Provider do
  @moduledoc """
  Supplies the identity details: presentation data for the UI, never an authorization decision.
  The provider is given the tenant of the request, so a real one can read tenant-scoped data.
  """

  use Arc.Identity.Provider, details: Samples.Identity.IdentityDetails

  @impl true
  def details(%Arc.Identity.Context{name: name, tenant: tenant}) do
    {:ok,
     %Samples.Identity.IdentityDetails{
       display_name: "Hello, #{name}",
       tenant: if(Arc.Tenancy.default?(tenant), do: "Default", else: tenant)
     }}
  end
end
