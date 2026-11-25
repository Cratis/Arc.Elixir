# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.AvailabilityTest do
  use ExUnit.Case, async: false

  alias Arc.Availability.Memory

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup do
    start_supervised!({ArcAvail.App, []})
    start_supervised!({Memory, app: ArcAvail.App})
    Process.delete(:vessel)
    :ok
  end

  defp run(module, wire, opts \\ []), do: Arc.execute(ArcAvail.App, {module, wire}, opts)

  defp as(roles, tenant \\ "acme"),
    do: [principal: Arc.Principal.new("u", "U", roles: roles), tenant: tenant]

  test "a part nothing gates runs" do
    assert %{authorized?: true, response: :pong} = run(ArcAvail.Fleet.Open.Ping, %{"id" => @id})
  end

  test "a scope gate closes everything under the namespace until the audience is granted" do
    refused = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
    refute refused.authorized?
    assert refused.authorization_failure_reason == "NotAvailable"
    assert Arc.CommandResult.status(refused) == 403

    Memory.grant({:tenant, "acme"}, "Plus")
    assert %{authorized?: true} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))

    assert %{authorized?: false} =
             run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([], "other"))

    Memory.withdraw({:tenant, "acme"}, "Plus")
    assert %{authorized?: false} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
  end

  test "a grant for an audience the definition does not declare never matches" do
    Memory.grant({:tenant, "acme"}, "Platinum")
    assert %{authorized?: false} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
  end

  test "the command's own not line holds together with the scope" do
    Memory.grant(:system, "Plus")
    Memory.grant({:user, "u"}, "Preview")
    assert %{authorized?: false} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
  end

  test "availability runs before authorization" do
    Memory.grant(:system, "Admin")
    Process.put(:vessel, %{reported: true})

    # available, but the role is missing: that is authorization's answer
    result = run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as([]))
    refute result.authorized?
    assert result.authorization_failure_reason != "NotAvailable"

    Memory.withdraw(:system, "Admin")
    result = run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as([]))
    assert result.authorization_failure_reason == "NotAvailable"
  end

  test "a module condition reads a provided value, and an absent value denies" do
    Memory.grant(:system, "Admin")
    result = run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as(["boss"]))
    assert result.authorization_failure_reason == "NotAvailable"

    Process.put(:vessel, %{reported: true})
    assert %{authorized?: true} = run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as(["boss"]))
  end

  test "a suspension wins over the gates and a resume lifts it" do
    Memory.grant(:system, "Plus")
    assert %{authorized?: true} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))

    Memory.suspend("Fleet/Gated")
    result = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
    assert result.authorization_failure_reason == "Suspended"
    assert Arc.CommandResult.status(result) == 403

    Memory.resume("Fleet/Gated")
    assert %{authorized?: true} = run(ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}, as([]))
  end

  test "a decision that cannot be made is a retryable 503, not a denial" do
    Memory.grant(:system, "Admin")
    Process.put(:vessel, :fail)
    result = run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as(["boss"]))
    assert result.authorized?
    assert result.retryable?
    assert Arc.CommandResult.status(result) == 503
    assert Arc.CommandResult.to_wire(result)["isRetryable"] == true
  end

  test "a provided value is read once per decision" do
    Memory.grant(:system, "Admin")
    Process.put(:vessel, %{reported: true})
    Process.put(:vessel_reads, 0)
    run(ArcAvail.Fleet.Plain.Admin, %{"id" => @id}, as(["boss"]))
    assert Process.get(:vessel_reads) == 1
  end

  test "a query is gated by the arguments it is asked with" do
    ok = Arc.query(ArcAvail.App, ArcAvail.Fleet.Plain.Vessels, :one, %{"vesselId" => "allowed"})
    assert ok.authorized?

    refused =
      Arc.query(ArcAvail.App, ArcAvail.Fleet.Plain.Vessels, :one, %{"vesselId" => "other"})

    refute refused.authorized?
    assert refused.authorization_failure_reason == "NotAvailable"
    assert Arc.QueryResult.to_wire(refused)["authorizationFailureReason"] == "NotAvailable"
    assert Arc.query(ArcAvail.App, ArcAvail.Fleet.Plain.Vessels, :all).authorized?
  end

  test "suspending a module suspends its queries" do
    Memory.suspend("ArcAvail.Fleet.Plain.Vessels")
    refused = Arc.query(ArcAvail.App, ArcAvail.Fleet.Plain.Vessels, :all)
    refute refused.authorized?
    assert refused.authorization_failure_reason == "Suspended"
  end

  describe "/.cratis/availability" do
    defp ask(opts \\ []) do
      ctx =
        Arc.Context.new(
          application: ArcAvail.App,
          tenant: "acme",
          principal: Arc.Principal.new("u", "U")
        )

      Arc.Availability.unavailable(ctx, opts)
    end

    test "lists what is not available with the reason" do
      Memory.suspend("ArcAvail.Fleet.Plain.Vessels.All")
      {:ok, list} = ask()
      names = Map.new(list, &{&1["name"], &1["reason"]})
      assert names["ArcAvail.Fleet.Gated.Dock"] == "NotAvailable"
      assert names["ArcAvail.Fleet.Plain.Vessels.All"] == "Suspended"
      refute Map.has_key?(names, "ArcAvail.Fleet.Open.Ping")
    end

    test "answers for one part and its arguments" do
      name = "ArcAvail.Fleet.Plain.Vessels.One"

      assert {:ok, [%{"reason" => "NotAvailable"}]} =
               ask(part: name, arguments: %{"vesselId" => "x"})

      assert {:ok, []} = ask(part: name, arguments: %{"vesselId" => "allowed"})
      assert {:ok, []} = ask(part: "No.Such.Part")
    end

    test "the observable query is routed, anonymous and re-run on change" do
      state = Arc.Application.state(ArcAvail.App)

      assert {descriptor, %{observable?: true, topics: [:arc_availability]}} =
               state.query_routes["/.cratis/availability"]

      result =
        Arc.Pipeline.execute_query(
          descriptor,
          hd(descriptor.queries),
          %{},
          Arc.Context.new(application: ArcAvail.App)
        )

      assert result.authorized?
      assert %{"unavailable" => [_ | _]} = result.data
    end

    test "a change notifies the observers" do
      Registry.register(Arc.Notifier.registry(ArcAvail.App), Arc.Availability.topic(), nil)
      Memory.grant(:system, "Plus")
      assert_receive {:arc_notify, :arc_availability}
    end
  end

  test "the manifest describes the application and decodes" do
    document = Arc.Availability.Manifest.build(ArcAvail.App)
    assert {:ok, _} = document |> Jason.encode!() |> Arc.Availability.Manifest.decode()

    assert Enum.any?(
             document["parts"],
             &(&1["name"] == "ArcAvail.Fleet.Gated.Dock" and &1["kind"] == "command")
           )

    assert [%{"kind" => "named"}] =
             for(
               p <- document["parts"],
               p["name"] == "ArcAvail.Fleet.Plain.Admin",
               g <- p["gates"],
               g["kind"] == "all",
               i <- g["items"],
               i["kind"] == "when",
               do: i["condition"]
             )

    assert Enum.any?(document["suspendable"], &(&1["kind"] == "part"))
  end
end
