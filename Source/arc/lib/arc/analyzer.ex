# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer do
  @moduledoc """
  A compile-time analyzer that checks your code against rules specific to Arc.

  The rules ship inside this package and run on every compile - on the command line, in your
  editor and in CI - and report standard Mix diagnostics. They are the Elixir counterpart of
  the Roslyn analyzers (`ARC####`) that ship with Arc for .NET; their ids are `ARCE####`.

  ## Setup

  Add the compiler to the project's `mix.exs`, ahead of the default compilers:

      def project do
        [
          # ...
          compilers: [:arc_analyzer] ++ Mix.compilers()
        ]
      end

  Or run `mix cratis_arc.install`, which makes the change for you. See the
  [code analysis documentation](https://www.cratis.io/arc/elixir/code-analysis/) for the rules,
  how to configure them, and how to suppress one.

  `:arc_analyzer` is separate from the `:arc` compiler, which generates TypeScript proxies after
  the Elixir compiler. The analyzer has to register its tracer before it.

  ## How it works

  This module is an Elixir compiler tracer. `Mix.Tasks.Compile.ArcAnalyzer` registers it before
  the Elixir compiler runs, and the compiler then reports every module it defines and every
  call a module makes into `Chronicle.*`. The tracer records those as facts - the Arc macros
  leave their declarations in module attributes, so the facts need no debug info - and once the
  Elixir compiler has finished, the rules in `Arc.Analyzer.Rules` run over the facts of the whole
  project. Facts are kept in a manifest so an incremental build still reports every finding.

  Only the project's own code is traced; dependencies are compiled without the tracer.
  """

  alias Arc.Analyzer.{Facts, ModuleFacts}

  @call_events [:remote_function, :remote_macro, :imported_function, :imported_macro]

  @doc false
  def trace({:on_module, _bytecode, _none}, %Macro.Env{module: module} = env)
      when is_atom(module) and not is_nil(module) do
    if Facts.active?(), do: Facts.record(module, :module, ModuleFacts.build(env))
    :ok
  end

  def trace({event, meta, callee, name, arity}, %Macro.Env{module: caller} = env)
      when event in @call_events and is_atom(callee) and is_atom(caller) and not is_nil(caller) do
    if Facts.active?() and chronicle?(callee) do
      Facts.record(caller, :call, %{
        caller: caller,
        callee: {callee, name, arity},
        function: env.function,
        file: env.file,
        line: Keyword.get(meta, :line, env.line)
      })
    end

    :ok
  end

  def trace(_event, _env), do: :ok

  defp chronicle?(module) do
    name = Atom.to_string(module)
    name == "Elixir.Chronicle" or String.starts_with?(name, "Elixir.Chronicle.")
  end
end
