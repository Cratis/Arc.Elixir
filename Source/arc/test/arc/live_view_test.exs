# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.LiveViewTest do
  # Not async: the Arc application supervisor and endpoint are registered by name.
  use Arc.Test.Case,
    application: ArcFixtures.App,
    configure: true,
    event_types: [ArcFixtures.Authors.AuthorRegistered],
    observable: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint ArcFixtures.Web.Endpoint

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup do
    ArcFixtures.Store.put([%ArcFixtures.Authors.Author{id: @id, name: "Ada"}])
    :ok
  end

  defp live_as(user), do: live(init_test_session(build_conn(), %{"user" => user}), "/authors")

  test "renders the query's data on the static render and when connected" do
    {:ok, view, html} = live(build_conn(), "/authors")

    assert html =~ "Ada"
    assert render(view) =~ "Ada"
  end

  test "an observable query pushes updates into the view" do
    {:ok, view, _html} = live(build_conn(), "/authors")

    ArcFixtures.Store.put([
      %ArcFixtures.Authors.Author{id: @id, name: "Ada"},
      %ArcFixtures.Authors.Author{id: "b", name: "Bob"}
    ])

    Arc.Notifier.notify(ArcFixtures.App, "authors")

    assert eventually(fn -> render(view) =~ "Bob" end)
  end

  test "validating a form shows the pipeline's errors on the field" do
    {:ok, view, _html} = live(build_conn(), "/authors")

    html = view |> form("#register", command: %{name: ""}) |> render_change()

    assert html =~ "must not be empty"
    assert html =~ ~s(class="error")
  end

  test "a valid form submits through the pipeline and appends the event", %{arc: arc} do
    {:ok, view, _html} = live(build_conn(), "/authors")

    html = view |> form("#register", command: %{name: "Grace"}) |> render_submit()

    assert html =~ "saved"
    Arc.Test.assert_appended(arc, ArcFixtures.Authors.AuthorRegistered, event_source_id: @id)
  end

  test "an invalid form submission shows errors and appends nothing", %{arc: arc} do
    {:ok, view, _html} = live(build_conn(), "/authors")

    html = view |> form("#register", command: %{name: "much too long a name"}) |> render_submit()

    refute html =~ "saved"
    assert html =~ "at most 10 characters"
    Arc.Test.refute_appended(arc, ArcFixtures.Authors.AuthorRegistered)
  end

  test "authorization follows the signed-in user on every call" do
    {:ok, anonymous, _} = live(build_conn(), "/authors")
    assert anonymous |> element("#rename") |> render_click() =~ "denied"

    {:ok, admin, _} = live_as(%{id: "u1", name: "root", roles: ["admin"]})
    assert admin |> element("#rename") |> render_click() =~ "previous-"
  end

  defp eventually(fun, attempts \\ 40) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(25) && eventually(fun, attempts - 1)
    end
  end
end
