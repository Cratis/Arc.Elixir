# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Rule do
  @moduledoc """
  The behaviour every analyzer rule implements.

  A rule has a stable id (`ARCE0001`), a description and a default severity, and looks at the
  project in up to three ways. Implement only the callbacks that fit:

    * `c:check_call/2` - called for every recorded call into `Chronicle.*`. Use it for
      misuse at a call site.
    * `c:check_module/2` - called for every module the project defines. Use it for how one
      module is declared.
    * `c:check_project/1` - called once. Use it for what only shows across modules, such as
      two commands resolving to the same route.

  All three run after compilation against the collected facts, so a rule can rely on the
  whole project being known - including modules compiled after the one being inspected.

  ## Example

      defmodule MyRule do
        @behaviour Arc.Analyzer.Rule

        def id, do: "ARCE9999"
        def description, do: "Commands must not be named Foo"
        def default_severity, do: :warning

        def check_module(%{kind: :command, module: Foo} = fact, _project) do
          [%Arc.Analyzer.Finding{
            module: fact.module, file: fact.file, line: fact.line,
            message: "rename Foo"
          }]
        end

        def check_module(_fact, _project), do: []
      end
  """

  alias Arc.Analyzer.{Finding, Project}

  @typedoc "How loudly a finding is reported. `:off` disables the rule."
  @type severity :: :error | :warning | :info | :off

  @doc "The stable rule id, such as `\"ARCE0001\"`. Never reused for another meaning."
  @callback id() :: String.t()

  @doc "One line saying what the rule checks."
  @callback description() :: String.t()

  @doc "The severity used when the project does not configure one."
  @callback default_severity() :: severity()

  @doc "Checks one recorded call into `Chronicle.*`."
  @callback check_call(Project.call_fact(), Project.t()) :: [Finding.t()]

  @doc "Checks one module the project defines."
  @callback check_module(Project.module_fact(), Project.t()) :: [Finding.t()]

  @doc "Checks the project as a whole."
  @callback check_project(Project.t()) :: [Finding.t()]

  @optional_callbacks check_call: 2, check_module: 2, check_project: 1

  @doc "The documentation page for a rule id."
  @spec documentation_url(String.t()) :: String.t()
  def documentation_url(id) do
    "https://www.cratis.io/arc/elixir/code-analysis/#{String.downcase(id)}/"
  end
end
