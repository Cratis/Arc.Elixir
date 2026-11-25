# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Appends do
  @moduledoc false

  # Which Chronicle event types a module refers to in its function bodies.
  #
  # A command returns the events it appends, so the event model cannot be read from a declaration.
  # It is read from the compiled module instead: the debug info holds the expanded code of every
  # function, and a struct literal in it is `{:%, _, [Module, fields]}`. The event types among the
  # structs a module builds are the events a command appends or a reactor emits. Patterns that
  # match a struct are found too, which is why a module's handled events are subtracted by callers.

  @doc "The event type modules referenced by the functions of `module`, in order of appearance."
  @spec in_module(module()) :: [module()]
  def in_module(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, {_, [debug_info: {:debug_info_v1, backend, data}]}} <-
           :beam_lib.chunks(path, [:debug_info]),
         {:ok, %{definitions: definitions}} <- backend.debug_info(:elixir_v1, module, data, []) do
      definitions
      |> Enum.flat_map(fn {_name, _kind, _meta, clauses} ->
        structs(Enum.map(clauses, &Tuple.to_list/1))
      end)
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  defp structs(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {:%, _meta, [module, _fields]} = node, acc when is_atom(module) ->
          {node, if(event_type?(module), do: [module | acc], else: acc)}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp event_type?(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__chronicle_event_type__, 1)
end
