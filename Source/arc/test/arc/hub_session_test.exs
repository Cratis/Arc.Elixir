# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.HubSessionTest do
  use ExUnit.Case, async: true

  alias Arc.Plug.HubSession
  alias Arc.QueryResult

  @before [%{"id" => "a", "name" => "Ada"}, %{"id" => "b", "name" => "Bob"}]
  @current [%{"id" => "a", "name" => "Ann"}, %{"id" => "c", "name" => "Cy"}]
  @changes %{
    "added" => [%{"id" => "c", "name" => "Cy"}],
    "replaced" => [%{"id" => "a", "name" => "Ann"}],
    "removed" => [%{"id" => "b", "name" => "Bob"}]
  }

  defp emit(mode, result, previous \\ nil, ordered? \\ false) do
    subscription = %{
      pid: self(),
      revision: 3,
      mode: mode,
      ordered?: ordered?,
      previous: previous
    }

    state = %{HubSession.new(__MODULE__, nil) | subscriptions: %{"q" => subscription}}
    {[message], state} = HubSession.result(state, "q", result)
    wire = Jason.decode!(message)
    assert wire["type"] == "QueryResult"
    assert wire["queryId"] == "q"
    assert wire["revision"] == 3
    {wire["payload"], state.subscriptions["q"]}
  end

  test "full mode sends snapshots without tracking previous data" do
    {wire, subscription} = emit(:full, %QueryResult{data: @current}, @before)
    assert wire["data"] == @current
    refute Map.has_key?(wire, "changeSet")
    assert subscription.previous == @before
  end

  test "delta mode sends the first snapshot without a change set" do
    {wire, subscription} = emit(:delta, %QueryResult{data: @before})
    assert wire["data"] == @before
    refute Map.has_key?(wire, "changeSet")
    assert subscription.previous == @before
  end

  test "ordered delta mode keeps subsequent snapshots without a change set" do
    {wire, subscription} = emit(:delta, %QueryResult{data: @current}, @before, true)
    assert wire["data"] == @current
    refute Map.has_key?(wire, "changeSet")
    assert subscription.previous == @current
  end

  test "unordered delta mode with identities sends only the change set" do
    {wire, subscription} = emit(:delta, %QueryResult{data: @current}, @before)
    refute Map.has_key?(wire, "data")
    assert wire["changeSet"] == @changes
    assert subscription.previous == @current
  end

  test "delta mode without identities retains the snapshot with value differences" do
    {wire, subscription} = emit(:delta, %QueryResult{data: [2, 3]}, [1, 2])
    assert wire["data"] == [2, 3]
    assert wire["changeSet"] == %{"added" => [3], "replaced" => [], "removed" => [1]}
    assert subscription.previous == [2, 3]
  end

  test "default mode always sends both the snapshot and the change set" do
    {first, _} = emit(:default, %QueryResult{data: @before})
    assert first["data"] == @before
    assert first["changeSet"] == %{"added" => @before, "replaced" => [], "removed" => []}

    {next, subscription} = emit(:default, %QueryResult{data: @current}, @before)
    assert next["data"] == @current
    assert next["changeSet"] == @changes
    assert subscription.previous == @current
  end

  test "failed and non-list results leave previous data unchanged" do
    for result <- [%QueryResult{data: @current, ready?: false}, %QueryResult{data: 1}] do
      {wire, subscription} = emit(:delta, result, @before)
      refute Map.has_key?(wire, "changeSet")
      assert subscription.previous == @before
    end
  end
end
