# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.MongoDB.ObservationTest do
  use MongoFixtures.Case

  alias MongoFixtures.Books.Book

  @a "11111111-1111-4111-8111-111111111111"
  @b "22222222-2222-4222-8222-222222222222"

  defp subscribe(ctx, id \\ :live) do
    [{descriptor, query}] =
      for d <- Arc.Application.artifacts(MongoFixtures.App).read_models,
          q <- d.queries,
          q.name == :live_books,
          do: {d, q}

    spec = %{
      owner: self(),
      id: id,
      descriptor: descriptor,
      query: query,
      args: %{},
      ctx: ctx,
      opts: []
    }

    {:ok, pid} = Arc.Subscription.start(MongoFixtures.App, spec)
    pid
  end

  defp next_titles(id \\ :live, timeout \\ 5_000) do
    assert_receive {:arc_query_result, ^id, result}, timeout
    Enum.map(result.data || [], & &1.title)
  end

  # The stream opens in the background, and an observer is told once it has, so insert when the
  # observer has seen the data it started with.
  test "a query re-runs when the collection changes", %{ctx: ctx} do
    subscribe(ctx)
    assert next_titles() == []

    Arc.MongoDB.insert({ctx, Book}, %Book{id: @a, title: "Dune"})
    assert eventually_titles() == ["Dune"]

    Arc.MongoDB.insert({ctx, Book}, %Book{id: @b, title: "Emma"})
    assert eventually_titles() == ["Dune", "Emma"]

    Arc.MongoDB.delete({ctx, Book}, @a)
    assert eventually_titles() == ["Emma"]
  end

  test "observers of a tenant hear their own database only", %{ctx: ctx} do
    acme = tenant("acme")
    globex = tenant("globex")
    subscribe(acme, :acme)
    subscribe(globex, :globex)
    assert next_titles(:acme) == []
    assert next_titles(:globex) == []
    # Each watcher tells its observers once its stream has opened.
    drain(:acme, [])
    drain(:globex, [])

    Arc.MongoDB.insert({acme, Book}, %Book{id: @a, title: "Acme's"})
    assert eventually_titles(:acme) == ["Acme's"]
    refute_receive {:arc_query_result, :globex, _}, 500

    Arc.MongoDB.insert({ctx, Book}, %Book{id: @b, title: "Default's"})
    refute_receive {:arc_query_result, :globex, _}, 300
  end

  test "one change stream serves every observer of a database", %{ctx: ctx} do
    for n <- 1..5, do: subscribe(ctx, {:live, n})
    for n <- 1..5, do: next_titles({:live, n})

    Arc.MongoDB.insert({ctx, Book}, %Book{id: @a, title: "Dune"})
    for n <- 1..5, do: assert(eventually_titles({:live, n}) == ["Dune"])

    watchers =
      DynamicSupervisor.which_children(Arc.MongoDB.Supervisor.watchers(MongoFixtures.App))

    assert length(watchers) == 1
  end

  test "a subscription that ends stops listening", %{ctx: ctx} do
    pid = subscribe(ctx)
    assert next_titles() == []
    Arc.Subscription.stop(pid)
    Process.sleep(100)

    registry = Arc.MongoDB.Watch.registry(MongoFixtures.App)
    assert Registry.select(registry, [{{:_, :_, :_}, [], [true]}]) == []
  end

  # Results arrive for the initial run, for the stream opening and for each change; wait for the
  # one that shows the expected data by reading until it does.
  defp eventually_titles(id \\ :live, tries \\ 20) do
    titles = next_titles(id)

    if titles == [] and tries > 0, do: eventually_titles(id, tries - 1), else: drain(id, titles)
  end

  # A change can produce more than one run (debounced); take the latest.
  defp drain(id, titles) do
    receive do
      {:arc_query_result, ^id, result} -> drain(id, Enum.map(result.data || [], & &1.title))
    after
      300 -> titles
    end
  end
end
