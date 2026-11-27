# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.CommandScenario do
  @moduledoc """
  A spec scenario for a command: the Elixir counterpart of `CommandScenario<TCommand>`.

  It runs the **real** pipeline (binding, validation, authorization, `provide/2`, `handle/2`, the
  Chronicle append and the reactors) against Chronicle's in-memory kernel; nothing is mocked. The
  spec has the shape of a Specification: facts are given, the command is executed **once**, and
  every `test` states one expectation with a `should_*` function.

      defmodule MyApp.Authors.ForRegisterAuthor.WhenRegistering.WithAValidName do
        use Cratis.Arc.Test.CommandScenario,
          application: MyApp.Arc,
          event_types: [MyApp.Authors.AuthorRegistered]

        alias MyApp.Authors.{AuthorRegistered, RegisterAuthor}

        setup_all %{scenario: scenario} do
          scenario =
            scenario
            |> execute(%RegisterAuthor{id: "ada", name: "Ada"}, as: principal("tester", ["maintainer"]))

          %{scenario: scenario}
        end

        test "should succeed", %{scenario: scenario}, do: should_be_successful(scenario)

        test "should append the author as registered", %{scenario: scenario} do
          scenario |> should_have_appended(%AuthorRegistered{name: "Ada"}, event_source_id: "ada")
        end
      end

  `use` starts the in-memory kernel once for the module (`lifecycle: :shared`, the default: the
  Specification's shared lifecycle) or before every test (`lifecycle: :per_test`, with `setup`
  instead of `setup_all`), puts the scenario in the context as `:scenario`, and imports this module
  and `Cratis.Arc.Test.Should`. Options: `:application` (required), `:lifecycle`, `:async` (default
  `true`) and every option of `Cratis.Chronicle.Testing.start_supervised_client/1` (`:event_types`,
  `:reactors`, `:reducers`, `:constraints`, ...).

  A scenario is an immutable value. **Given** and **Because** functions return the next scenario,
  **should** functions check it and return it, so they chain.

  ## Given and because

    * `given_events/3` - facts that already happened, appended before the command
    * `execute/3` - runs the command, as `:as` (a `Cratis.Arc.Principal`; none means anonymous)
    * `principal/2` - an authenticated principal with roles

  ## Should

    * `should_be_successful/1`, `should_not_be_successful/1`
    * `should_not_be_authorized/1`
    * `should_have_validation_errors/1,2`, `should_have_exception/1,2`
    * `should_have_constraint_violation/1,2`, `should_have_concurrency_violation/1`
    * `should_respond_with/2`
    * `should_have_appended/2,3`, `should_not_have_appended/2,3`, `should_have_appended_exactly/2`,
      `should_not_have_appended_any_events/1`

  Events are matched by an exact struct, an event type module, or a 1-arity predicate, and only the
  events appended **by the command** (and what its reactors appended) count, not the given ones.
  """

  import Cratis.Arc.Test.Scenarios,
    only: [appended_since: 2, describe: 1, fail: 1, fail: 3, matches?: 2]

  alias Cratis.Arc.{CommandResult, Principal}
  alias Cratis.Arc.Test.Scenarios

  defstruct [:application, :client, :result, baseline: 0]

  @type t :: %__MODULE__{}

  defmacro __using__(opts), do: Scenarios.using(__MODULE__, opts)

  @doc "A scenario for `application` against a Chronicle test client."
  @spec new(module(), atom()) :: t()
  def new(application, client), do: %__MODULE__{application: application, client: client}

  # -- given and because -----------------------------------------------------------------------

  @doc """
  Applies a reusable given context: a module with `given/1` (or `{module, argument}` for `given/2`), a
  1-arity function. Contexts compose: a context may `given/2` another one.
  """
  @spec given(t(), module() | {module(), term()} | (t() -> t())) :: t()
  def given(%__MODULE__{} = scenario, context), do: Scenarios.apply_given(scenario, [context])

  @doc "Appends `events` (one event or a list) to an event source before the command runs."
  @spec given_events(t(), String.t(), struct() | [struct()]) :: t()
  def given_events(%__MODULE__{} = scenario, event_source_id, events) do
    Scenarios.given_events(scenario.client, event_source_id, events)
    scenario
  end

  @doc """
  Executes `command` (a struct, or `{module, wire_map}`) and keeps its result.

  Options: `:as` is the `Cratis.Arc.Principal` the command runs as; the rest are the options of
  `Cratis.Arc.execute/3`.
  """
  @spec execute(t(), struct() | {module(), map()}, keyword()) :: t()
  def execute(%__MODULE__{} = scenario, command, opts \\ []) do
    {principal, opts} = Keyword.pop(opts, :as)
    opts = if principal, do: Keyword.put(opts, :principal, principal), else: opts
    opts = Keyword.put_new(opts, :chronicle, client: scenario.client)

    baseline = length(Scenarios.all_events(scenario.client))
    result = Cratis.Arc.execute(scenario.application, command, opts)
    Cratis.Chronicle.Testing.wait_for_observers(scenario.client)

    %{scenario | result: result, baseline: baseline}
  end

  @doc "An authenticated principal with `roles`."
  @spec principal(String.t(), [String.t()]) :: Principal.t()
  def principal(name \\ "tester", roles \\ []), do: Cratis.Arc.Test.principal(name, roles)

  @doc "The `Cratis.Arc.CommandResult` of the executed command."
  @spec result(t()) :: CommandResult.t()
  def result(%__MODULE__{result: nil}),
    do: fail("the scenario has not executed a command yet; call execute/3 first")

  def result(%__MODULE__{result: result}), do: result

  # -- should: the result ----------------------------------------------------------------------

  @doc "The command should have succeeded: authorized, valid and without exceptions."
  @spec should_be_successful(t()) :: t()
  def should_be_successful(scenario) do
    result = result(scenario)

    if CommandResult.success?(result),
      do: scenario,
      else:
        fail(
          "Expected the command to succeed, but it did not: #{inspect(summary(result), pretty: true)}"
        )
  end

  @doc "The command should not have succeeded, for whatever reason."
  @spec should_not_be_successful(t()) :: t()
  def should_not_be_successful(scenario) do
    if CommandResult.success?(result(scenario)),
      do: fail("Expected the command not to succeed, but it did"),
      else: scenario
  end

  @doc "The caller should have been refused before the command ran."
  @spec should_not_be_authorized(t()) :: t()
  def should_not_be_authorized(scenario) do
    result = result(scenario)

    if result.authorized?,
      do:
        fail(
          "Expected the caller not to be authorized, but it was: #{inspect(summary(result), pretty: true)}"
        ),
      else: scenario
  end

  @doc """
  The command should have been refused by validation. With a member (an atom) at least one result
  should be for that member; with a string at least one message should contain it.
  """
  @spec should_have_validation_errors(t(), atom() | String.t() | nil) :: t()
  def should_have_validation_errors(scenario, expectation \\ nil) do
    results = rule_results(result(scenario))

    cond do
      results == [] ->
        fail(
          "Expected validation errors, got: #{inspect(summary(result(scenario)), pretty: true)}"
        )

      expectation == nil ->
        scenario

      is_atom(expectation) and Enum.any?(results, &(expectation in &1.members)) ->
        scenario

      is_binary(expectation) and
          Enum.any?(results, &String.contains?(to_string(&1.message), expectation)) ->
        scenario

      true ->
        fail(
          "Expected a validation error for #{inspect(expectation)}",
          Enum.map(results, &Map.take(&1, [:members, :message])),
          expectation
        )
    end
  end

  @doc "The command should have failed with an exception, optionally one whose message contains `text`."
  @spec should_have_exception(t(), String.t() | nil) :: t()
  def should_have_exception(scenario, text \\ nil) do
    messages = result(scenario).exception_messages

    cond do
      messages == [] -> fail("Expected an exception, but the command raised none")
      text == nil -> scenario
      Enum.any?(messages, &String.contains?(&1, text)) -> scenario
      true -> fail("Expected an exception mentioning #{inspect(text)}", messages, text)
    end
  end

  @doc "Chronicle should have refused the append because a constraint (by name, when given) was violated."
  @spec should_have_constraint_violation(t(), String.t() | nil) :: t()
  def should_have_constraint_violation(scenario, name \\ nil) do
    violations =
      Enum.filter(result(scenario).validation_results, &(&1.reason == "constraintViolation"))

    cond do
      violations == [] ->
        fail(
          "Expected a constraint violation, got: #{inspect(summary(result(scenario)), pretty: true)}"
        )

      name == nil ->
        scenario

      Enum.any?(violations, &(&1.reason_detail == name)) ->
        scenario

      true ->
        fail(
          "Expected a violation of constraint #{inspect(name)}",
          Enum.map(violations, & &1.reason_detail),
          name
        )
    end
  end

  @doc "Chronicle should have refused the append because of a concurrency violation."
  @spec should_have_concurrency_violation(t()) :: t()
  def should_have_concurrency_violation(scenario) do
    if Enum.any?(result(scenario).validation_results, &(&1.reason == "concurrencyViolation")),
      do: scenario,
      else:
        fail(
          "Expected a concurrency violation, got: #{inspect(summary(result(scenario)), pretty: true)}"
        )
  end

  @doc """
  The command's response should match `expected`: a 1-arity predicate, a map whose keys and values
  are all in the response, or any other value, compared with `===`.
  """
  @spec should_respond_with(t(), term()) :: t()
  def should_respond_with(scenario, expected) do
    response = result(scenario).response

    ok? =
      cond do
        is_function(expected, 1) ->
          expected.(response) == true

        is_map(expected) and is_map(response) ->
          Enum.all?(expected, fn {k, v} -> Map.fetch(response, k) == {:ok, v} end)

        true ->
          response === expected
      end

    if ok?,
      do: scenario,
      else: fail("Expected the response to match #{inspect(expected)}", response, expected)
  end

  # -- should: the events ----------------------------------------------------------------------

  @doc """
  The command should have appended an event matching `matcher` (an exact struct, an event type
  module or a predicate). Options: `:event_source_id` limits it to one event source, `:count` asks
  for exactly that many instead of at least one.
  """
  @spec should_have_appended(t(), struct() | module() | (struct() -> boolean()), keyword()) :: t()
  def should_have_appended(scenario, matcher, opts \\ []) do
    matched = matching(scenario, matcher, opts)
    count = Keyword.get(opts, :count)

    cond do
      count != nil and length(matched) != count ->
        fail(
          "Expected #{count} appended event(s) matching #{describe(matcher)}, got #{length(matched)}",
          appended(scenario),
          matcher
        )

      count == nil and matched == [] ->
        fail(
          "Expected the command to append #{describe(matcher)}, but it appended: #{inspect(appended(scenario), pretty: true)}",
          appended(scenario),
          matcher
        )

      true ->
        scenario
    end
  end

  @doc "The command should not have appended an event matching `matcher` (see `should_have_appended/3`)."
  @spec should_not_have_appended(t(), struct() | module() | (struct() -> boolean()), keyword()) ::
          t()
  def should_not_have_appended(scenario, matcher, opts \\ []) do
    case matching(scenario, matcher, opts) do
      [] ->
        scenario

      matched ->
        fail(
          "Expected no appended event matching #{describe(matcher)}, but found: #{inspect(matched, pretty: true)}",
          matched,
          matcher
        )
    end
  end

  @doc """
  The command should have appended exactly these events, in this order. Each element is a matcher
  as in `should_have_appended/3`.
  """
  @spec should_have_appended_exactly(t(), [struct() | module() | (struct() -> boolean())]) :: t()
  def should_have_appended_exactly(scenario, matchers) when is_list(matchers) do
    events = appended(scenario)

    ok? =
      length(events) == length(matchers) and
        Enum.zip(events, matchers)
        |> Enum.all?(fn {event, matcher} -> matches?(event, matcher) end)

    if ok?,
      do: scenario,
      else:
        fail(
          "Expected the command to append exactly #{inspect(Enum.map(matchers, &describe/1))}",
          events,
          matchers
        )
  end

  @doc "The command should not have appended any event at all."
  @spec should_not_have_appended_any_events(t()) :: t()
  def should_not_have_appended_any_events(scenario) do
    case appended(scenario) do
      [] ->
        scenario

      events ->
        fail(
          "Expected the command to append nothing, but it appended: #{inspect(events, pretty: true)}",
          events,
          []
        )
    end
  end

  # -- internals -------------------------------------------------------------------------------

  defp appended(%__MODULE__{} = scenario),
    do: scenario |> appended_pairs() |> Enum.map(&elem(&1, 1))

  defp appended_pairs(%__MODULE__{client: client, baseline: baseline}),
    do: appended_since(client, baseline)

  defp matching(scenario, matcher, opts) do
    only = Keyword.get(opts, :event_source_id)

    for {event_source_id, event} <- appended_pairs(scenario),
        only == nil or event_source_id == only,
        matches?(event, matcher),
        do: event
  end

  defp rule_results(result),
    do:
      Enum.reject(
        result.validation_results,
        &(&1.reason in ["constraintViolation", "concurrencyViolation"])
      )

  defp summary(%CommandResult{} = result),
    do:
      Map.take(result, [
        :authorized?,
        :validation_results,
        :exception_messages,
        :authorization_failure_reason
      ])
end
