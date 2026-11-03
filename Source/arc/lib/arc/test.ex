# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Test do
  @moduledoc """
  ExUnit support that runs the real Arc pipelines against Chronicle's in-memory kernel.

      defmodule MyApp.RegisterAuthorTest do
        use Arc.Test.Case,
          application: MyApp.Arc,
          event_types: [MyApp.Authors.AuthorRegistered]

        test "registers an author", %{arc: arc} do
          result = Arc.Test.execute(arc, %MyApp.Authors.RegisterAuthor{id: "...", name: "Ada"})

          Arc.Test.assert_success(result)
          Arc.Test.assert_appended(arc, MyApp.Authors.AuthorRegistered, event_source_id: "...")
        end
      end

  Validation, authorization, binding and the Chronicle append all run for real; nothing is
  mocked. Reactors and reducers run synchronously after each append, as in `Chronicle.Testing`.
  Each test gets its own kernel, so `async: true` is safe.
  """

  import ExUnit.Assertions

  alias Arc.{CommandResult, Principal, QueryResult, ValidationResult}

  defmodule Scenario do
    @moduledoc "The application and Chronicle test client of one test."
    defstruct [:application, :client]
  end

  @doc "Builds a scenario for `application` using a Chronicle test client."
  @spec scenario(module(), atom()) :: Scenario.t()
  def scenario(application, client), do: %Scenario{application: application, client: client}

  @doc "Executes a command. Accepts the options of `Arc.execute/3`."
  @spec execute(Scenario.t(), struct() | {module(), map()}, keyword()) :: CommandResult.t()
  def execute(%Scenario{} = scenario, command, opts \\ []),
    do: Arc.execute(scenario.application, command, with_client(scenario, opts))

  @doc "Executes a query. Accepts the options of `Arc.query/5`."
  @spec query(Scenario.t(), module(), atom(), map(), keyword()) :: QueryResult.t()
  def query(%Scenario{} = scenario, read_model, name, args \\ %{}, opts \\ []),
    do: Arc.query(scenario.application, read_model, name, args, with_client(scenario, opts))

  defp with_client(scenario, opts), do: Keyword.put_new(opts, :chronicle, client: scenario.client)

  @doc "Waits until Chronicle's in-memory observers have processed every appended event."
  @spec wait_for_observers(Scenario.t()) :: :ok
  def wait_for_observers(%Scenario{client: client}),
    do: Chronicle.Testing.wait_for_observers(client)

  @doc "An authenticated principal."
  @spec principal(String.t(), [String.t()]) :: Principal.t()
  def principal(name \\ "tester", roles \\ []), do: Principal.new(name, name, roles: roles)

  @doc "Asserts the command succeeded: authorized, valid and without exceptions."
  @spec assert_success(CommandResult.t() | QueryResult.t()) :: true
  def assert_success(%{} = result) do
    ok? =
      case result do
        %CommandResult{} -> CommandResult.success?(result)
        %QueryResult{} -> QueryResult.success?(result)
      end

    assert ok?, "expected success, got: #{inspect(summary(result))}"
  end

  @doc "Asserts the result was rejected by validation, optionally for a member."
  @spec assert_invalid(CommandResult.t() | QueryResult.t(), atom() | nil) :: true
  def assert_invalid(result, member \\ nil) do
    results = result.validation_results
    assert results != [], "expected validation failure, got: #{inspect(summary(result))}"

    if member do
      assert Enum.any?(results, fn %ValidationResult{members: m} -> member in m end),
             "expected a result for #{inspect(member)}, got: #{inspect(results)}"
    else
      true
    end
  end

  @doc "Asserts the caller was not authorized."
  @spec assert_forbidden(CommandResult.t() | QueryResult.t()) :: true
  def assert_forbidden(result),
    do:
      assert(result.authorized? == false, "expected forbidden, got: #{inspect(summary(result))}")

  @doc "Asserts an event was appended. See `Chronicle.Testing.Assertions.assert_appended/3`."
  @spec assert_appended(Scenario.t(), struct() | module() | (struct() -> boolean()), keyword()) ::
          true
  def assert_appended(%Scenario{client: client}, matcher, opts \\ []),
    do: Chronicle.Testing.Assertions.assert_appended(client, matcher, opts)

  @doc "Asserts no matching event was appended."
  @spec refute_appended(Scenario.t(), struct() | module() | (struct() -> boolean()), keyword()) ::
          false
  def refute_appended(%Scenario{client: client}, matcher, opts \\ []),
    do: Chronicle.Testing.Assertions.refute_appended(client, matcher, opts)

  defp summary(%CommandResult{} = r),
    do:
      Map.take(r, [
        :authorized?,
        :validation_results,
        :exception_messages,
        :authorization_failure_reason
      ])

  defp summary(%QueryResult{} = r),
    do: Map.take(r, [:authorized?, :ready?, :validation_results, :exception_messages])
end

defmodule Arc.Test.Case do
  @moduledoc """
  `ExUnit.CaseTemplate` that starts an in-memory Chronicle client per test and puts an
  `Arc.Test.Scenario` in the context as `:arc`.

  Options: `:application` (required) and every option of `Chronicle.Testing.start_supervised_client/1`
  (`:event_types`, `:reactors`, `:reducers`, `:constraints`, ...). Pass `observable: true` to also
  start the application's supervisor for observable-query tests; such tests cannot run with
  `async: true` because the supervisor is registered by name.
  """

  use ExUnit.CaseTemplate

  using opts do
    {application, opts} = Keyword.pop!(opts, :application)
    {observable, chronicle_opts} = Keyword.pop(opts, :observable, false)

    quote do
      setup do
        {:ok, client} = Chronicle.Testing.start_supervised_client(unquote(chronicle_opts))
        on_exit(fn -> Chronicle.Testing.stop_supervised_client(client) end)

        if unquote(observable), do: start_supervised!(unquote(application))

        %{arc: Arc.Test.scenario(unquote(application), client), chronicle: client}
      end
    end
  end
end
