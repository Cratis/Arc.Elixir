# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.AvailabilityLiveViewTest do
  use ExUnit.Case, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Arc.Availability.Memory

  setup do
    start_supervised!({ArcAvail.App, []})
    start_supervised!({Memory, app: ArcAvail.App})

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        arc_application: ArcAvail.App,
        arc_tenant: "acme",
        arc_principal: Arc.Principal.new("u", "U"),
        arc_availability: 0
      }
    }

    {:ok, socket: socket}
  end

  defp render_part(socket, version) do
    assigns = %{socket: socket, version: version}

    rendered_to_string(~H"""
    <Arc.LiveView.Availability.available socket={@socket} version={@version} command={ArcAvail.Fleet.Gated.Dock}>
      <button>Dock</button>
      <:unavailable>Not in your plan</:unavailable>
    </Arc.LiveView.Availability.available>
    """)
  end

  test "hides a part the caller cannot use and shows it once the audience is granted", %{
    socket: socket
  } do
    html = render_part(socket, 0)
    assert html =~ "Not in your plan"
    refute html =~ "<button>"

    Memory.grant({:tenant, "acme"}, "Plus")
    html = render_part(socket, 1)
    assert html =~ "<button>Dock</button>"
    refute html =~ "Not in your plan"
  end

  test "available?/3 answers for a query with its arguments", %{socket: socket} do
    part = {ArcAvail.Fleet.Plain.Vessels, :one}
    assert Arc.LiveView.available?(socket, part, %{"vesselId" => "allowed"})
    refute Arc.LiveView.available?(socket, part, %{"vesselId" => "x"})
  end
end

defmodule Arc.AvailabilityPubSubTest do
  use ExUnit.Case, async: false

  alias Arc.Availability.Memory

  setup do
    previous = Application.get_env(:cratis_arc, ArcAvail.App)

    Application.put_env(:cratis_arc, ArcAvail.App,
      availability: [
        definition: ArcAvail.Fleet.Vessels.Availability,
        audience_source: Memory,
        suspension_source: Memory,
        pubsub: ArcAvail.PubSub
      ]
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cratis_arc, ArcAvail.App, previous),
        else: Application.delete_env(:cratis_arc, ArcAvail.App)

      Arc.Application.refresh(ArcAvail.App)
    end)

    start_supervised!({Phoenix.PubSub, name: ArcAvail.PubSub})
    start_supervised!({ArcAvail.App, []})
    start_supervised!({Memory, app: ArcAvail.App})
    :ok
  end

  test "a change announced by another node re-runs the observers on this one" do
    Registry.register(Arc.Notifier.registry(ArcAvail.App), Arc.Availability.topic(), nil)

    # Another node: its notification reaches this node only through PubSub.
    Phoenix.PubSub.broadcast(
      ArcAvail.PubSub,
      Arc.Availability.pubsub_topic(ArcAvail.App),
      {:arc_availability_changed, ArcAvail.App}
    )

    assert_receive {:arc_notify, :arc_availability}
  end

  test "a change on this node is announced to the other nodes" do
    Phoenix.PubSub.subscribe(ArcAvail.PubSub, Arc.Availability.pubsub_topic(ArcAvail.App))
    task = Task.async(fn -> Memory.grant(:system, "Plus") end)
    Task.await(task)
    assert_receive {:arc_availability_changed, ArcAvail.App}
  end
end
