# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.ModuleFacts do
  @moduledoc false
  # Reads what the analyzer needs from a module that is still open (the `:on_module` tracer
  # event fires while attributes can be read). The Arc macros leave their declarations in module
  # attributes, so nothing here needs the module's debug info.

  alias Arc.Authorization

  @doc "Builds the module fact for the module `env` is compiling."
  @spec build(Macro.Env.t()) :: Arc.Analyzer.Project.module_fact()
  def build(%Macro.Env{module: module} = env) do
    kind = kind(module)
    module_authorization = authorization(module, kind)

    %{
      module: module,
      file: env.file,
      line: env.line,
      kind: kind,
      schema?: Module.has_attribute?(module, :arc_fields),
      struct?: Module.defines?(module, {:__struct__, 0}),
      handle?: Module.defines?(module, {:handle, 2}),
      authorization: module_authorization,
      queries: queries(module, kind),
      ignore: ignore(module)
    }
  end

  defp kind(module) do
    cond do
      Module.has_attribute?(module, :arc_response) -> :command
      Module.has_attribute?(module, :arc_model) -> :read_model
      true -> nil
    end
  end

  defp authorization(_module, nil), do: nil

  defp authorization(module, _kind),
    do: module |> attribute(:arc_authorization, nil) |> Authorization.normalize()

  defp queries(module, :read_model) do
    module
    |> attribute(:arc_queries, [])
    |> Enum.reverse()
    |> Enum.map(fn {name, opts, observable?, _doc} ->
      %{
        name: name,
        observable?: observable?,
        watch: Keyword.get(opts, :watch, []),
        topics: Keyword.get(opts, :topics, []),
        authorization: query_authorization(opts)
      }
    end)
  end

  defp queries(_module, _kind), do: []

  defp query_authorization(opts) do
    if Keyword.has_key?(opts, :authorize),
      do: Authorization.normalize(Keyword.get(opts, :authorize)),
      else: nil
  end

  defp ignore(module) do
    # One `@arc_analyzer ignore: [...]` is a keyword list; several are a list of them when the
    # attribute accumulates. Accept both.
    declared = attribute(module, :arc_analyzer, [])
    declared = if Keyword.keyword?(declared), do: [declared], else: List.wrap(declared)

    declared
    |> Enum.flat_map(fn
      opts when is_list(opts) -> opts |> Keyword.get(:ignore, []) |> List.wrap()
      _ -> []
    end)
    |> Enum.map(&to_string/1)
  end

  defp attribute(module, name, default) do
    if Module.has_attribute?(module, name),
      do: Module.get_attribute(module, name),
      else: default
  end
end
