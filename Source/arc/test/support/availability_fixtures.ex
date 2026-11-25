# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ArcAvail.Fleet.Vessels.Availability do
  @moduledoc false
  use Arc.Availability.Definition

  audience("Plus", "Customers on Plus")
  audience("Admin", "Operators")
  audience("Preview", "Preview tenants")

  block("Paid", "Sold with Plus", for: ["Plus", "Admin"])

  scope("ArcAvail.Fleet.Gated", with: "Paid")

  value("vessel", ArcAvail.VesselValue)
end

defmodule ArcAvail.VesselValue do
  @moduledoc false
  @behaviour Arc.Availability.Definition

  @impl true
  def value(_ambient) do
    count = Process.get(:vessel_reads, 0)
    Process.put(:vessel_reads, count + 1)

    case Process.get(:vessel) do
      :fail -> {:error, :store_down}
      nil -> :absent
      vessel -> {:ok, vessel}
    end
  end
end

defmodule ArcAvail.HasReported do
  @moduledoc false
  @behaviour Arc.Availability.Condition

  @impl true
  def evaluate(read) do
    case read.("vessel.reported") do
      {:ok, true} -> :available
      {:ok, _} -> :unavailable
      :absent -> :unknown
    end
  end
end

defmodule ArcAvail.Fleet.Open.Ping do
  @moduledoc false
  use Arc.Command
  allow_anonymous()

  schema do
    field :id, :uuid, key: true
  end

  def handle(_command, _ctx), do: {:ok, :pong}
end

defmodule ArcAvail.Fleet.Gated.Dock do
  @moduledoc false
  use Arc.Command
  allow_anonymous()
  available(not: "Preview")

  schema do
    field :vessel_id, :string
  end

  def handle(_command, _ctx), do: {:ok, :docked}
end

defmodule ArcAvail.Fleet.Plain.Admin do
  @moduledoc false
  use Arc.Command
  authorize roles: ["boss"]
  available(for: "Admin", when: ArcAvail.HasReported)

  schema do
    field :id, :uuid, key: true
  end

  def handle(_command, _ctx), do: {:ok, :done}
end

defmodule ArcAvail.Fleet.Plain.Vessels do
  @moduledoc false
  use Arc.ReadModel, model: ArcAvail.Vessel
  allow_anonymous()

  @query many: true
  def all(_args, _ctx), do: {:ok, []}

  @query many: true,
         available: [
           when: Arc.Availability.Condition.equal("arguments.vesselId", "allowed")
         ],
         params: [vessel_id: {:string, optional: true}]
  def one(_args, _ctx), do: {:ok, []}
end

defmodule ArcAvail.Vessel do
  @moduledoc false
  defstruct [:id]
end

defmodule ArcAvail.App do
  use Arc.Application,
    otp_app: :cratis_arc,
    artifacts: [
      ArcAvail.Fleet.Open.Ping,
      ArcAvail.Fleet.Gated.Dock,
      ArcAvail.Fleet.Plain.Admin,
      ArcAvail.Fleet.Plain.Vessels
    ],
    availability: [
      definition: ArcAvail.Fleet.Vessels.Availability,
      audience_source: Arc.Availability.Memory,
      suspension_source: Arc.Availability.Memory
    ]
end
