# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.RulesTest do
  # The rules over hand-built facts: no compiler involved.
  use ExUnit.Case, async: true

  alias Arc.Analyzer.{Config, Project, Runner, Rules}
  alias Arc.Analyzer.Rules.{ARCE0001, ARCE0002, ARCE0003, ARCE0004, ARCE0005}

  @open %{roles: [], policy: nil, allow_anonymous: false, authenticated?: false}

  defp module_fact(module, overrides \\ []) do
    Map.merge(
      %{
        module: module,
        file: "/app/lib/#{inspect(module)}.ex",
        line: 3,
        kind: nil,
        schema?: false,
        struct?: false,
        handle?: false,
        authorization: nil,
        queries: [],
        ignore: []
      },
      Map.new(overrides)
    )
  end

  defp command(module, overrides \\ []),
    do:
      module_fact(
        module,
        [kind: :command, schema?: true, struct?: true, handle?: true, authorization: @open] ++
          overrides
      )

  defp project(facts, calls \\ []),
    do: %Project{modules: Map.new(facts, &{&1.module, &1}), calls: calls, config: %Config{}}

  defp query(name, overrides \\ []),
    do:
      Map.merge(
        %{name: name, observable?: false, watch: [], topics: [], authorization: nil},
        Map.new(overrides)
      )

  test "the rule ids are unique and stable in format" do
    ids = Enum.map(Rules.all(), & &1.id())

    assert ids == Enum.uniq(ids)
    assert Enum.all?(ids, &(&1 =~ ~r/^ARCE\d{4}$/))
  end

  describe "ARCE0001" do
    test "flags a schema with handle/2 that is not a command" do
      fact = module_fact(Foo, schema?: true, struct?: true, handle?: true)

      assert [%{message: message, module: Foo}] = ARCE0001.check_module(fact, project([fact]))
      assert message =~ "use Arc.Command"
    end

    test "accepts a command, and a module without a schema" do
      assert ARCE0001.check_module(command(Foo), project([])) == []

      assert ARCE0001.check_module(module_fact(Foo, handle?: true, struct?: true), project([])) ==
               []
    end
  end

  describe "ARCE0002" do
    test "flags a command that is anonymous and restricted" do
      fact =
        command(Foo,
          authorization: %{@open | allow_anonymous: true, roles: ["admin"], authenticated?: true}
        )

      assert [%{message: message}] = ARCE0002.check_module(fact, project([fact]))
      assert message =~ "Foo"
    end

    test "flags a query that is anonymous and restricted" do
      auth = %{@open | allow_anonymous: true, policy: :p, authenticated?: true}

      fact =
        module_fact(Lst,
          kind: :read_model,
          authorization: @open,
          queries: [query(:all, authorization: auth)]
        )

      assert [%{message: message}] = ARCE0002.check_module(fact, project([fact]))
      assert message =~ "Lst.all/2"
    end

    test "accepts anonymous alone, restricted alone, and a query that overrides the module" do
      anonymous = command(A, authorization: %{@open | allow_anonymous: true})
      restricted = command(B, authorization: %{@open | roles: ["x"], authenticated?: true})

      overriding =
        module_fact(C,
          kind: :read_model,
          authorization: %{@open | roles: ["x"], authenticated?: true},
          queries: [query(:open, authorization: %{@open | allow_anonymous: true})]
        )

      for fact <- [anonymous, restricted, overriding],
          do: assert(ARCE0002.check_module(fact, project([fact])) == [])
    end
  end

  describe "ARCE0003" do
    test "flags an observable query with nothing to watch" do
      fact = module_fact(Lst, kind: :read_model, queries: [query(:live, observable?: true)])

      assert [%{message: message}] = ARCE0003.check_module(fact, project([fact]))
      assert message =~ "Lst.live/2"
    end

    test "accepts watch, topics, and plain queries" do
      fact =
        module_fact(Lst,
          kind: :read_model,
          queries: [
            query(:a, observable?: true, watch: [Foo]),
            query(:b, observable?: true, topics: ["t"]),
            query(:c)
          ]
        )

      assert ARCE0003.check_module(fact, project([fact])) == []
    end
  end

  describe "ARCE0004" do
    defp call(caller, callee),
      do: %{
        caller: caller,
        callee: callee,
        function: {:handle, 2},
        file: "/app/lib/x.ex",
        line: 9
      }

    test "flags a command appending to Chronicle itself" do
      fact = command(Foo)

      assert [%{line: 9}] =
               ARCE0004.check_call(call(Foo, {Chronicle, :append, 2}), project([fact]))

      assert [_] =
               ARCE0004.check_call(
                 call(Foo, {Chronicle.EventSequences.EventLog, :append_many, 3}),
                 project([fact])
               )
    end

    test "accepts other calls, and appends from other modules" do
      fact = command(Foo)
      other = module_fact(Bar)

      assert ARCE0004.check_call(call(Foo, {Chronicle, :read_model, 2}), project([fact])) == []
      assert ARCE0004.check_call(call(Bar, {Chronicle, :append, 2}), project([other])) == []
    end
  end

  describe "ARCE0005" do
    test "flags two commands resolving to the same route" do
      a = command(A.Authors.Register)
      b = command(B.Authors.Register)

      findings = ARCE0005.check_project(project([a, b]))

      assert length(findings) == 2
      assert Enum.all?(findings, &(&1.message =~ "/api/authors/register"))
    end

    test "honours segments_to_skip" do
      a = command(A.Authors.Register)
      b = command(B.Authors.Register)
      project = %{project([a, b]) | config: %Config{segments_to_skip: 0}}

      assert ARCE0005.check_project(project) == []
    end

    test "flags two queries on one route, but not a command and a query" do
      a = module_fact(A.Lists, kind: :read_model, queries: [query(:all)])
      b = module_fact(B.Lists, kind: :read_model, queries: [query(:all)])
      command = command(A.Lists.All)

      assert length(ARCE0005.check_project(project([a, b]))) == 2
      assert ARCE0005.check_project(project([a, command])) == []
    end
  end

  describe "the runner" do
    test "stamps the id, the configured severity and the documentation link" do
      fact = module_fact(Lst, kind: :read_model, queries: [query(:live, observable?: true)])
      config = Config.from(rules: [{"ARCE0003", :error}])

      assert [diagnostic] = Runner.run(project([fact]), config, [ARCE0003])
      assert diagnostic.severity == :error
      assert diagnostic.details == %{rule: "ARCE0003"}
      assert diagnostic.message =~ "ARCE0003: "
      assert diagnostic.message =~ "https://www.cratis.io/arc/elixir/code-analysis/arce0003/"
      assert diagnostic.position == 3
    end

    test "skips a rule that is off, and every rule when disabled" do
      fact = module_fact(Lst, kind: :read_model, queries: [query(:live, observable?: true)])

      assert Runner.run(project([fact]), Config.from(rules: [{"ARCE0003", :off}]), [ARCE0003]) ==
               []

      assert Runner.run(project([fact]), Config.from(enabled: false), [ARCE0003]) == []
    end

    test "drops a finding the module ignores" do
      fact =
        module_fact(Lst,
          kind: :read_model,
          ignore: ["ARCE0003"],
          queries: [query(:live, observable?: true)]
        )

      assert Runner.run(project([fact]), Config.from([]), [ARCE0003]) == []
    end

    test "reports :info findings as Mix information diagnostics" do
      fact = module_fact(Lst, kind: :read_model, queries: [query(:live, observable?: true)])
      config = Config.from(rules: [{"ARCE0003", :info}])

      assert [%{severity: :information}] = Runner.run(project([fact]), config, [ARCE0003])
    end
  end

  describe "the configuration" do
    test "defaults to enabled with every rule at its default severity" do
      config = Config.from([])

      assert config.enabled
      assert Config.severity(config, ARCE0002) == :error
      assert Config.severity(config, ARCE0001) == :warning
    end

    test "accepts a keyword list, a map and a list of tuples" do
      for rules <- [[{"ARCE0001", :off}], %{"ARCE0001" => :off}, [ARCE0001: :off]] do
        assert Config.severity(Config.from(rules: rules), ARCE0001) == :off
      end
    end

    test "reports unknown rules and invalid severities" do
      config = Config.from(rules: [{"ARCE9999", :off}, {"ARCE0001", :loud}])

      assert [unknown, invalid] = Enum.sort(Config.problems(config))
      assert unknown =~ "ARCE0001 has invalid severity"
      assert invalid =~ "unknown rule \"ARCE9999\""
    end
  end
end
