# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule CountersTest do
  use Cratis.Arc.Test.Case,
    application: Counters.Arc,
    configure: true,
    event_types: [Counters.CounterIncremented]

  import Plug.Conn
  import Plug.Test

  alias Counters.Counting.IncrementCounter

  defp call(conn), do: Counters.Router.call(conn, Counters.Router.init([]))

  test "incrementing records the event", %{arc: arc} do
    id = Cratis.Arc.new_id()

    Cratis.Arc.Test.assert_success(
      Cratis.Arc.Test.execute(arc, {IncrementCounter, %{"id" => id, "by" => 3}})
    )

    Cratis.Arc.Test.assert_appended(arc, %Counters.CounterIncremented{by: 3}, event_source_id: id)
  end

  test "the declarative rules reject an out-of-range amount", %{arc: arc} do
    result =
      Cratis.Arc.Test.execute(
        arc,
        {IncrementCounter, %{"id" => Cratis.Arc.new_id(), "by" => 1000}}
      )

    Cratis.Arc.Test.assert_invalid(result, :by)
    Cratis.Arc.Test.refute_appended(arc, Counters.CounterIncremented)
  end

  test "the plain Plug router serves the Arc contract", %{arc: arc} do
    id = Cratis.Arc.new_id()

    conn =
      conn(:post, "/api/counting/increment-counter", Jason.encode!(%{id: id, by: 2}))
      |> put_req_header("content-type", "application/json")
      |> call()

    assert conn.status == 200
    Cratis.Arc.Test.assert_appended(arc, Counters.CounterIncremented, event_source_id: id)
    assert call(conn(:get, "/health")).resp_body == "ok"
  end
end
