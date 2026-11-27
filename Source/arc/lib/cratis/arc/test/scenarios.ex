# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.Scenarios do
  @moduledoc false

  # What the command and query scenarios share: starting the in-memory kernel for a spec module,
  # seeding events, reading what was appended, and matching events.

  alias Cratis.Chronicle.EventSequences.EventLog
  alias Cratis.Chronicle.Events.AppendedEvent
  alias Cratis.Chronicle.Testing
  alias Cratis.Chronicle.Testing.InMemoryKernel

  @doc "The `use` body: starts the kernel once per module (`:shared`) or per test (`:per_test`)."
  def using(scenario_module, opts) do
    {application, opts} = Keyword.pop!(opts, :application)
    {lifecycle, opts} = Keyword.pop(opts, :lifecycle, :shared)
    {async, chronicle_opts} = Keyword.pop(opts, :async, true)

    setup = if lifecycle == :per_test, do: :setup, else: :setup_all

    quote do
      use ExUnit.Case, async: unquote(async)

      import Cratis.Arc.Test.Should
      import unquote(scenario_module)

      unquote(setup)() do
        {:ok, client} = Cratis.Chronicle.Testing.start_supervised_client(unquote(chronicle_opts))

        ExUnit.Callbacks.on_exit(fn ->
          Cratis.Chronicle.Testing.stop_supervised_client(client)
        end)

        %{scenario: unquote(scenario_module).new(unquote(application), client)}
      end
    end
  end

  @doc "Appends `events` to an event source, as the given facts of a scenario."
  def given_events(client, event_source_id, events) do
    case EventLog.append_many(to_string(event_source_id), List.wrap(events), client: client) do
      :ok ->
        :ok

      other ->
        raise ExUnit.AssertionError, message: "the given events were refused: #{inspect(other)}"
    end

    Testing.wait_for_observers(client)
  end

  @doc "Every event in the store, decoded, in append order."
  def all_events(client) do
    case Testing.kernel_for(client) do
      nil ->
        []

      kernel ->
        event_types = InMemoryKernel.event_types(kernel)

        kernel
        |> InMemoryKernel.all_wire_events()
        |> Enum.map(&AppendedEvent.from_wire(&1, event_types))
    end
  end

  @doc "The events appended after the first `baseline`, as `{event_source_id, event}` pairs."
  def appended_since(client, baseline) do
    client
    |> all_events()
    |> Enum.drop(baseline)
    |> Enum.reject(&is_nil(&1.event))
    |> Enum.map(&{&1.context.event_source_id, &1.event})
  end

  @doc "Whether `event` matches an exact struct, an event type module or a 1-arity predicate."
  def matches?(event, matcher) when is_function(matcher, 1), do: matcher.(event) == true
  def matches?(event, matcher) when is_atom(matcher), do: match?(%{__struct__: ^matcher}, event)
  def matches?(event, matcher), do: event == matcher

  @doc "A short, readable description of a matcher for failure messages."
  def describe(matcher) when is_atom(matcher), do: inspect(matcher)
  def describe(matcher) when is_function(matcher), do: "an event satisfying the predicate"
  def describe(matcher), do: inspect(matcher)

  @doc "Raises an `ExUnit.AssertionError` carrying `message` and, when given, the two sides."
  def fail(message, left \\ nil, right \\ nil) do
    raise ExUnit.AssertionError, message: message, left: left, right: right
  end
end
