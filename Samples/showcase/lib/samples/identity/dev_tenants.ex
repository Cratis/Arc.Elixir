# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Identity.DevTenants do
  @moduledoc "The tenants a development tool offers to select. Not how a tenant is resolved."

  @behaviour Arc.Identity.TenantsProvider

  @impl true
  def tenants do
    [
      %Arc.Identity.Tenant{id: "acme", name: "ACME"},
      %Arc.Identity.Tenant{id: "globex", name: "Globex"}
    ]
  end
end
