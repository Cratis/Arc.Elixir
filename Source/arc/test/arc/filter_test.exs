# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.FilterTest do
  # Not async: the application configuration is global.
  use Arc.Test.Case,
    application: ArcFixtures.App,
    configure: true,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  alias ArcFixtures.Authors.Registration.RegisterAuthor

  defmodule OnlyEditors do
    @behaviour Arc.Filter

    @impl true
    def on_command(ctx, %Arc.Descriptor{name: "RegisterAuthor"}), do: require_editor(ctx)
    def on_command(_ctx, _descriptor), do: :ok

    @impl true
    def on_query(ctx, _descriptor, %{name: :all_authors}), do: require_editor(ctx)

    def on_query(_ctx, _descriptor, %{name: :by_id}),
      do: {:error, Arc.Validation.error("No.", [])}

    def on_query(_ctx, _descriptor, _query), do: :ok

    defp require_editor(ctx) do
      if "editor" in ctx.principal.roles,
        do: :ok,
        else: {:unauthorized, "Role 'editor' is required."}
    end
  end

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  setup do
    previous = Application.get_env(:cratis_arc, ArcFixtures.App)

    Application.put_env(
      :cratis_arc,
      ArcFixtures.App,
      Keyword.put(previous, :filters, [OnlyEditors])
    )

    Arc.Application.refresh(ArcFixtures.App)
    on_exit(fn -> Application.put_env(:cratis_arc, ArcFixtures.App, previous) end)
    :ok
  end

  defp as(roles), do: [principal: Arc.Principal.new("u", "U", roles: roles)]

  test "a command a filter rejects is unauthorized with the filter's reason", %{arc: arc} do
    result =
      Arc.execute(
        ArcFixtures.App,
        %RegisterAuthor{id: struct(ArcFixtures.Authors.AuthorId, value: @id), name: "Ada"},
        as([])
      )

    refute result.authorized?
    assert result.authorization_failure_reason == "Role 'editor' is required."
    Arc.Test.refute_appended(arc, ArcFixtures.Authors.AuthorRegistered)
  end

  test "a command the filter lets through runs", %{arc: arc} do
    result =
      Arc.execute(
        ArcFixtures.App,
        %RegisterAuthor{id: struct(ArcFixtures.Authors.AuthorId, value: @id), name: "Ada"},
        as(["editor"])
      )

    assert result.authorized?
    Arc.Test.assert_appended(arc, ArcFixtures.Authors.AuthorRegistered, event_source_id: @id)
  end

  test "queries are filtered too" do
    denied =
      Arc.query(ArcFixtures.App, ArcFixtures.Authors.Listing.Authors, :all_authors, %{}, as([]))

    refute denied.authorized?

    allowed =
      Arc.query(
        ArcFixtures.App,
        ArcFixtures.Authors.Listing.Authors,
        :all_authors,
        %{},
        as(["editor"])
      )

    assert allowed.authorized?
  end

  test "a filter can reject with validation results" do
    result =
      Arc.query(
        ArcFixtures.App,
        ArcFixtures.Authors.Listing.Authors,
        :by_id,
        %{id: @id},
        as(["editor"])
      )

    assert [%{message: "No."}] = result.validation_results
  end

  test "a filter that only knows commands is skipped for queries" do
    defmodule CommandsOnly do
      @behaviour Arc.Filter
      @impl true
      def on_command(_ctx, _descriptor), do: {:unauthorized, "never"}
    end

    previous = Application.get_env(:cratis_arc, ArcFixtures.App)

    Application.put_env(
      :cratis_arc,
      ArcFixtures.App,
      Keyword.put(previous, :filters, [CommandsOnly])
    )

    Arc.Application.refresh(ArcFixtures.App)

    result = Arc.query(ArcFixtures.App, ArcFixtures.Authors.Listing.Authors, :all_authors)
    assert result.authorized?
  end
end
