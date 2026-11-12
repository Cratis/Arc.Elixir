# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Project do
  @moduledoc """
  The facts the tracer collected about the project being compiled.

  Rules receive this struct so they can look across modules. It holds only the consuming
  project's own code - dependencies are never traced.

    * `:modules` - `%{module => module_fact}`, one per module the project defines.
    * `:calls` - a call fact for every call the project makes into `Chronicle.*`.
    * `:config` - the `Arc.Analyzer.Config` in effect, for rules that depend on it.

  ## Module facts

    * `:module`, `:file`, `:line` - where the module is defined.
    * `:kind` - `:command`, `:read_model`, or `nil` for any other module.
    * `:schema?` - whether the module declares an `Arc.Schema`.
    * `:struct?` and `:handle?` - whether it defines a struct and a `handle/2` function.
    * `:authorization` - the normalized `Arc.Authorization` requirement of a command or read
      model (`nil` otherwise).
    * `:queries` - for a read model, one map per `@query` / `@observe`: `:name`,
      `:observable?`, `:watch`, `:topics` and its own `:authorization` (`nil` when it
      inherits the module's).
    * `:ignore` - the rule ids switched off with `@arc_analyzer ignore: [...]`.

  ## Call facts

    * `:caller` - the module the call is made from.
    * `:callee` - `{module, function, arity}`.
    * `:function` - `{name, arity}` of the calling function, or `nil` outside a function.
    * `:file`, `:line` - the call site.
  """

  @enforce_keys [:modules, :calls]
  defstruct modules: %{}, calls: [], config: nil

  @type module_fact :: %{required(atom()) => term()}
  @type call_fact :: %{
          caller: module(),
          callee: {module(), atom(), non_neg_integer()},
          function: {atom(), non_neg_integer()} | nil,
          file: String.t(),
          line: pos_integer()
        }
  @type t :: %__MODULE__{
          modules: %{module() => module_fact()},
          calls: [call_fact()],
          config: Arc.Analyzer.Config.t() | nil
        }

  @doc "Returns the module fact for `module`, or `nil` when the project does not define it."
  @spec module_fact(t(), module()) :: module_fact() | nil
  def module_fact(%__MODULE__{modules: modules}, module), do: Map.get(modules, module)
end
