# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.AuthorsLiveTest do
  # Not async: the endpoint and the Arc application are registered by name.
  use Arc.Test.Case,
    application: Library.Arc,
    configure: true,
    event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint Library.Web.Endpoint

  # The in-memory kernel has no read-model query surface, so the list renders empty here.
  # The form, validation, authorization and recording are what this page exercises.
  test "the form shows the pipeline's validation errors as you type" do
    {:ok, view, _html} = live(build_conn(), "/live/authors")

    html = view |> form("#register", command: %{name: "A"}) |> render_change()

    assert html =~ "at least 2 characters"
  end

  test "registering through the form records the event and resets the form", %{arc: arc} do
    {:ok, view, _html} = live(build_conn(), "/live/authors")

    html = view |> form("#register", command: %{name: "Ada Lovelace"}) |> render_submit()

    assert html =~ "Registered."
    Arc.Test.assert_appended(arc, Library.Authors.AuthorRegistered, [])
  end

  test "a reserved name is rejected by the command" do
    {:ok, view, _html} = live(build_conn(), "/live/authors")

    html = view |> form("#register", command: %{name: "admin"}) |> render_submit()

    assert html =~ "That name is reserved."
  end
end
