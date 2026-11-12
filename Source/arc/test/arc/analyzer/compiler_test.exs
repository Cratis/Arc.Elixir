# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.CompilerTest do
  # Runs the real `mix compile` task, with the compiler on, over a throwaway project.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  @register """
  defmodule Fx.Authors.Register do
    use Arc.Schema

    schema do
      field :name, :string
    end

    def handle(_command, _ctx), do: :ok
  end
  """

  @rename """
  defmodule Fx.Authors.Rename do
    use Arc.Command
    authorize allow_anonymous: true, roles: ["admin"]

    schema do
      field :id, :uuid, key: true
    end

    def handle(command, _ctx) do
      Chronicle.append(command, command)
      {:ok, 1}
    end
  end

  defmodule Fx.Authors.Listing do
    use Arc.ReadModel, model: Fx.Authors.Rename

    @query many: true
    def all(_args, _ctx), do: {:ok, []}

    @observe many: true
    def live(_args, _ctx), do: {:ok, []}
  end
  """

  setup %{tmp_dir: dir} do
    previous = Application.get_env(:cratis_arc, :analyzer)
    id = System.unique_integer([:positive])
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/register.ex"), unique(@register, id))
    File.write!(Path.join(dir, "lib/rename.ex"), unique(@rename, id))

    File.write!(Path.join(dir, "mix.exs"), """
    defmodule ArcFixture#{id}.MixProject do
      use Mix.Project

      def project,
        do: [
          app: :arc_fixture,
          version: "0.0.1",
          # Consolidating would replace this VM's protocols with ones that know no test deps.
          consolidate_protocols: false,
          compilers: [:arc_analyzer] ++ Mix.compilers()
        ]
    end
    """)

    Application.delete_env(:cratis_arc, :analyzer)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cratis_arc, :analyzer, previous),
        else: Application.delete_env(:cratis_arc, :analyzer)
    end)

    {:ok, dir: dir, id: id}
  end

  defp unique(source, id), do: String.replace(source, "Fx.", "Fx#{id}.")

  # The rule ids reported in the output. A failed build exits before Mix hands the
  # diagnostics back, so the output is what a developer sees, and what the tests read.
  defp rules({_status, _diagnostics, output}) do
    ~r/(ARCE\d{4}):/
    |> Regex.scan(output, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Runs the real `mix compile` task over the fixture project, with the compiler on.
  defp compile(dir, args \\ []) do
    # The fixture project has no dependencies, so Mix prunes Arc from the code path. Loaded
    # modules stay loaded.
    Code.ensure_all_loaded(Application.spec(:cratis_arc, :modules))
    Code.ensure_all_loaded(Application.spec(:cratis_chronicle, :modules))

    parent = self()
    original_path = :code.get_path()

    output =
      capture_io(:stderr, fn ->
        result =
          Mix.Project.in_project(
            :arc_fixture,
            dir,
            [build_path: Path.join(dir, "_build")],
            fn _ ->
              Mix.Task.Compiler.reenable()
              Mix.Task.reenable("compile")
              Mix.Task.reenable("compile.all")
              Mix.Task.reenable("compile.elixir")
              Mix.Task.reenable("compile.arc_analyzer")
              run_compile(args)
            end
          )

        send(parent, {:result, result})
      end)

    # Mix pruned the code path to the fixture project's; give the other tests theirs back.
    :code.set_path(original_path)

    receive do
      {:result, {status, diagnostics}} -> {status, diagnostics, output}
    end
  end

  defp run_compile(args) do
    Mix.Task.run("compile", args)
  catch
    :exit, {:shutdown, 1} -> {:error, Mix.Task.Compiler.diagnostics()}
  end

  test "reports each rule as a diagnostic with file, line, rule id and a link", %{dir: dir} do
    {_status, _diagnostics, output} = result = compile(dir)

    assert rules(result) == ["ARCE0001", "ARCE0002", "ARCE0003", "ARCE0004"]
    assert output =~ "https://www.cratis.io/arc/elixir/code-analysis/arce0001/"

    assert output =~ "lib/rename.ex:10"
  end

  test "re-reports the findings when nothing changed", %{dir: dir} do
    first = compile(dir)
    second = compile(dir)

    assert rules(second) == rules(first)
  end

  test "keeps the findings of files an incremental build did not recompile", %{dir: dir} do
    compile(dir)

    File.write!(
      Path.join(dir, "lib/register.ex"),
      File.read!(Path.join(dir, "lib/register.ex")) <> "\n"
    )

    assert compile(dir) |> rules() == ["ARCE0001", "ARCE0002", "ARCE0003", "ARCE0004"]
  end

  test "drops the findings of a file that was fixed or removed", %{dir: dir} do
    compile(dir)
    File.rm!(Path.join(dir, "lib/register.ex"))

    assert compile(dir) |> rules() == ["ARCE0002", "ARCE0003", "ARCE0004"]
  end

  test "a configured severity fails the build", %{dir: dir} do
    Application.put_env(:cratis_arc, :analyzer, rules: [{"ARCE0003", :error}])

    assert {:error, _diagnostics, output} = compile(dir)
    assert output =~ "ARCE0003"
  end

  test "an error severity rule fails the build by default", %{dir: dir} do
    assert {:error, _diagnostics, _output} = compile(dir)
  end

  test "a rule set to :off is not reported", %{dir: dir} do
    Application.put_env(:cratis_arc, :analyzer, rules: [{"ARCE0002", :off}, {"ARCE0003", :off}])

    assert compile(dir) |> rules() == ["ARCE0001", "ARCE0004"]
  end

  test "the global switch turns the analyzer off", %{dir: dir} do
    Application.put_env(:cratis_arc, :analyzer, enabled: false)

    assert {_status, _diagnostics, output} = compile(dir)
    refute output =~ "ARCE"
  end

  test "--warnings-as-errors fails the build on a warning", %{dir: dir} do
    Application.put_env(:cratis_arc, :analyzer, rules: [{"ARCE0002", :off}])

    assert {:error, _diagnostics, _output} = compile(dir, ["--warnings-as-errors"])
  end

  test "a module can ignore a rule", %{dir: dir, id: id} do
    File.write!(
      Path.join(dir, "lib/register.ex"),
      unique(
        String.replace(
          @register,
          "use Arc.Schema",
          "use Arc.Schema\n  @arc_analyzer ignore: [\"ARCE0001\"]"
        ),
        id
      )
    )

    refute "ARCE0001" in (compile(dir) |> rules())
  end

  test "warns about a rule id that does not exist", %{dir: dir} do
    Application.put_env(:cratis_arc, :analyzer, rules: [{"ARCE9999", :off}])

    {_status, _diagnostics, output} = compile(dir)
    assert output =~ "unknown rule \"ARCE9999\""
  end
end
