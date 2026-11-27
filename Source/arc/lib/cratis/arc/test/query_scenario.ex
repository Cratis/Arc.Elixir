# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Test.QueryScenario do
  @moduledoc """
  A spec scenario for a read-model query: the Elixir counterpart of `QueryScenario<TReadModel>`.

  The query runs through the real pipeline (arguments, authorization, paging, sorting). The
  in-memory Chronicle kernel does not run read-model queries, so a query whose data comes from a
  projection needs the development kernel; a query over state the application keeps itself, or one
  that only needs arguments and authorization checked, runs here.

      defmodule MyApp.Authors.ForAuthorsQueries.WhenListingAuthors.AsAMaintainer do
        use Cratis.Arc.Test.QueryScenario, application: MyApp.Arc

        setup_all %{scenario: scenario} do
          scenario =
            scenario
            |> query(MyApp.Authors.Queries, :authors, %{}, as: principal("tester", ["maintainer"]))

          %{scenario: scenario}
        end

        test "should be successful", %{scenario: scenario}, do: should_be_successful(scenario)
        test "should return the authors", %{scenario: scenario}, do: should_return_items(scenario, 2)
      end

  `use` behaves as in `Cratis.Arc.Test.CommandScenario` (same options, same `:scenario` context
  entry and lifecycle).

    * `given_events/3` - facts that already happened
    * `query/5` - runs the query, as `:as`
    * `should_be_successful/1`, `should_not_be_successful/1`, `should_not_be_authorized/1`,
      `should_have_validation_errors/1,2`
    * `should_return/2`, `should_return_items/2`, `should_return_nothing/1`, `should_be_ready/1`
  """

  import Cratis.Arc.Test.Scenarios, only: [fail: 1, fail: 3]

  alias Cratis.Arc.{Principal, QueryResult}
  alias Cratis.Arc.Test.Scenarios

  defstruct [:application, :client, :result]

  @type t :: %__MODULE__{}

  defmacro __using__(opts), do: Scenarios.using(__MODULE__, opts)

  @doc "A scenario for `application` against a Chronicle test client."
  @spec new(module(), atom()) :: t()
  def new(application, client), do: %__MODULE__{application: application, client: client}

  @doc """
  Applies a reusable given context: a module with `given/1` (or `{module, argument}` for `given/2`), a
  1-arity function. Contexts compose: a context may `given/2` another one.
  """
  @spec given(t(), module() | {module(), term()} | (t() -> t())) :: t()
  def given(%__MODULE__{} = scenario, context), do: Scenarios.apply_given(scenario, [context])

  @doc "Appends `events` (one event or a list) to an event source before the query runs."
  @spec given_events(t(), String.t(), struct() | [struct()]) :: t()
  def given_events(%__MODULE__{} = scenario, event_source_id, events) do
    Scenarios.given_events(scenario.client, event_source_id, events)
    scenario
  end

  @doc """
  Runs the query `name` of `read_model` with `args` and keeps the result. `:as` is the principal;
  the rest are the options of `Cratis.Arc.query/5`.
  """
  @spec query(t(), module(), atom(), map(), keyword()) :: t()
  def query(%__MODULE__{} = scenario, read_model, name, args \\ %{}, opts \\ []) do
    {principal, opts} = Keyword.pop(opts, :as)
    opts = if principal, do: Keyword.put(opts, :principal, principal), else: opts
    opts = Keyword.put_new(opts, :chronicle, client: scenario.client)

    result = Cratis.Arc.query(scenario.application, read_model, name, args, opts)
    %{scenario | result: result}
  end

  @doc "An authenticated principal with `roles`."
  @spec principal(String.t(), [String.t()]) :: Principal.t()
  def principal(name \\ "tester", roles \\ []), do: Cratis.Arc.Test.principal(name, roles)

  @doc "The `Cratis.Arc.QueryResult` of the query."
  @spec result(t()) :: QueryResult.t()
  def result(%__MODULE__{result: nil}),
    do: fail("the scenario has not run a query yet; call query/5 first")

  def result(%__MODULE__{result: result}), do: result

  @doc "The query should have succeeded: ready, authorized, valid and without exceptions."
  @spec should_be_successful(t()) :: t()
  def should_be_successful(scenario) do
    result = result(scenario)

    if QueryResult.success?(result),
      do: scenario,
      else:
        fail(
          "Expected the query to succeed, but it did not: #{inspect(summary(result), pretty: true)}"
        )
  end

  @doc "The query should not have succeeded, for whatever reason."
  @spec should_not_be_successful(t()) :: t()
  def should_not_be_successful(scenario) do
    if QueryResult.success?(result(scenario)),
      do: fail("Expected the query not to succeed, but it did"),
      else: scenario
  end

  @doc "The query should be ready (an observable query has its first data)."
  @spec should_be_ready(t()) :: t()
  def should_be_ready(scenario),
    do: if(result(scenario).ready?, do: scenario, else: fail("Expected the query to be ready"))

  @doc "The caller should have been refused before the query ran."
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

  @doc "The query should have been refused by validation, optionally for a member (atom) or with a message containing a string."
  @spec should_have_validation_errors(t(), atom() | String.t() | nil) :: t()
  def should_have_validation_errors(scenario, expectation \\ nil) do
    results = result(scenario).validation_results

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

  @doc """
  The data should match `expected`: a 1-arity predicate, or any value compared with `===`. A list
  of items is compared as a whole.
  """
  @spec should_return(t(), term()) :: t()
  def should_return(scenario, expected) do
    data = result(scenario).data

    ok? = if is_function(expected, 1), do: expected.(data) == true, else: data === expected

    if ok?,
      do: scenario,
      else: fail("Expected the query to return #{inspect(expected)}", data, expected)
  end

  @doc "The query should return a list of exactly `count` items."
  @spec should_return_items(t(), non_neg_integer()) :: t()
  def should_return_items(scenario, count) do
    case result(scenario).data do
      items when is_list(items) and length(items) == count ->
        scenario

      items when is_list(items) ->
        fail("Expected #{count} item(s), got #{length(items)}", items, count)

      other ->
        fail("Expected a list of #{count} item(s), got #{inspect(other)}", other, count)
    end
  end

  @doc "The query should return nothing: `nil` or an empty list."
  @spec should_return_nothing(t()) :: t()
  def should_return_nothing(scenario) do
    case result(scenario).data do
      nil ->
        scenario

      [] ->
        scenario

      other ->
        fail(
          "Expected the query to return nothing, got #{inspect(other, pretty: true)}",
          other,
          []
        )
    end
  end

  defp summary(%QueryResult{} = result),
    do: Map.take(result, [:authorized?, :ready?, :validation_results, :exception_messages])
end
