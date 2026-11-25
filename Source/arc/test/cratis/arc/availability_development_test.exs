# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.AvailabilityDevelopmentTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias Cratis.Arc.Availability.{Development, Memory}
  alias Cratis.Arc.Structure

  setup do
    start_supervised!({ArcAvail.App, []})
    start_supervised!({Memory, app: ArcAvail.App})
    on_exit(fn -> :persistent_term.erase({Development, ArcAvail.App}) end)
    :ok
  end

  defp dock(opts \\ []),
    do:
      Cratis.Arc.execute(
        ArcAvail.App,
        {ArcAvail.Fleet.Gated.Dock, %{"vesselId" => "v"}},
        Keyword.merge([principal: Cratis.Arc.Principal.new("u", "U"), tenant: "acme"], opts)
      )

  defp call(conn),
    do: Cratis.Arc.Plug.call(conn, Cratis.Arc.Plug.init(application: ArcAvail.App))

  defp authenticated(conn), do: assign(conn, :arc_principal, Cratis.Arc.Test.principal())

  defp overrides(changes), do: Map.merge(Development.none(), changes)

  # The slice of Dock, and the module it sits in, as paths.
  defp dock_slice do
    part =
      Enum.find(
        Cratis.Arc.Application.state(ArcAvail.App).availability.list,
        &(&1.name == "ArcAvail.Fleet.Gated.Dock")
      )

    Structure.location_segments(part.module, part.feature, part.slice)
  end

  defp dock_path, do: Enum.join(dock_slice(), "/")
  defp dock_module, do: hd(dock_slice())

  test "an audience switched on opens the gates it satisfies" do
    refute dock().authorized?

    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"enabledAudiences" => ["Plus"]}))

    assert dock().authorized?
  end

  test "an audience switched off closes the gates that need it" do
    Memory.grant({:tenant, "acme"}, "Plus")
    assert dock().authorized?

    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"disabledAudiences" => ["Plus"]}))

    refute dock().authorized?
  end

  test "an audience the definition does not declare is never held" do
    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"enabledAudiences" => ["Platinum"]}))

    refute dock().authorized?
  end

  test "a path switched off is not available whatever its gates say" do
    Memory.grant(:system, "Plus")
    assert dock().authorized?

    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"disabledPaths" => [dock_path()]}))

    refused = dock()
    refute refused.authorized?
    assert refused.authorization_failure_reason == "NotAvailable"
  end

  test "a path switched on is available whatever its gates say" do
    refute dock().authorized?

    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"enabledPaths" => [dock_module()]}))

    assert dock().authorized?
  end

  test "switching off wins over switching on" do
    {:ok, _} =
      Development.apply_overrides(
        ArcAvail.App,
        overrides(%{"enabledPaths" => [dock_module()], "disabledPaths" => [dock_module()]})
      )

    refute dock().authorized?
  end

  test "a change tells the observers so they decide again" do
    Registry.register(
      Cratis.Arc.Notifier.registry(ArcAvail.App),
      Cratis.Arc.Availability.topic(),
      nil
    )

    {:ok, _} =
      Development.apply_overrides(ArcAvail.App, overrides(%{"enabledAudiences" => ["Plus"]}))

    assert_receive {:arc_notify, :arc_availability}
  end

  test "overrides are cleaned" do
    assert %{"enabledAudiences" => ["Plus"], "disabledPaths" => []} =
             Development.normalize(%{
               "enabledAudiences" => [" Plus ", "", "Plus", 3],
               "other" => 1
             })
  end

  describe "over HTTP" do
    test "the model carries the audiences and the overrides in force" do
      conn = conn(:get, "/.cratis/availability/model") |> authenticated() |> call()
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Enum.map(body["audiences"], & &1["name"]) == ["Plus", "Admin", "Preview"]
      assert body["overrides"] == Development.none()
    end

    test "posting overrides applies them" do
      conn =
        conn(
          :post,
          "/.cratis/availability/overrides",
          Jason.encode!(%{"enabledAudiences" => ["Plus"]})
        )
        |> put_req_header("content-type", "application/json")
        |> authenticated()
        |> call()

      assert conn.status == 200
      assert dock().authorized?
    end

    test "the routes need an authenticated caller" do
      assert (conn(:get, "/.cratis/availability/model") |> call()).status == 401
    end

    test "the structure lists the modules, features and slices" do
      conn = conn(:get, "/.cratis/structure") |> authenticated() |> call()
      assert conn.status == 200
      assert %{"modules" => [_ | _]} = Jason.decode!(conn.resp_body)
    end
  end

  describe "the structure" do
    test "nests a part by module, feature and slice" do
      state = Cratis.Arc.Application.state(ArcAvail.App)

      %{"modules" => modules} =
        Structure.build(state.commands, state.read_models, state.config[:segments_to_skip])

      all = collect_slices(modules)

      assert Enum.any?(
               all,
               &(&1["path"] =~ "Gated" and
                   Enum.any?(&1["parts"], fn p ->
                     p["fullName"] == "ArcAvail.Fleet.Gated.Dock" and p["kind"] == "Command"
                   end))
             )
    end

    test "a path covers what is beneath it by whole segments" do
      assert Structure.within?(["Fleet", "Quality", "Scores"], "Fleet/Quality")
      assert Structure.within?(["Fleet", "Quality"], "Fleet/Quality")
      refute Structure.within?(["Fleets", "Quality"], "Fleet")
      refute Structure.within?(["Fleet"], "Fleet/Quality")
      refute Structure.within?(["Fleet"], "")
    end
  end

  defp collect_slices(modules) do
    Enum.flat_map(modules, fn m -> m["slices"] ++ features(m["features"]) end)
  end

  defp features(features),
    do: Enum.flat_map(features, fn f -> f["slices"] ++ features(f["features"]) end)
end
