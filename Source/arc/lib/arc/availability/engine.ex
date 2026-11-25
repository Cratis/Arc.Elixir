# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Availability.Engine do
  @moduledoc """
  The availability engine: a port of the Arc for .NET engine, with the same three values and the
  same order of decision. It decides over manifest-shaped data (string-keyed maps, see
  `Arc.Availability.Manifest`), so declared code and a manifest file are decided by one mechanism.

  An expression is `:available`, `:unavailable` or `:unknown`. Only `:available` opens a gate; an
  unknown (an absent value, an audience that cannot be decided) denies, exactly as an unavailable
  does. Values are read lazily and at most once per decision.

  The environment given to `decide/3`:

    * `:ambient` - values by name that always come from the server (`"tenant"`, `"identity"`,
      `"arguments"`). Nothing a provider or an argument says can replace them
    * `:audiences` - a function returning `{:ok, audience_names}`, `:undecided` or `{:error, reason}`
    * `:values` - providers of further context values by name, each a one-argument function over the
      ambient map returning `{:ok, value}`, `:absent` or `{:error, reason}`
    * `:blocks` - the gates of the named blocks, by name
    * `:conditions` - modules implementing `Arc.Availability.Condition`, by name
    * `:suspended` - the suspended paths (see `Arc.Availability.Paths`)
  """

  alias Arc.Availability.Paths

  @type outcome :: :available | :unavailable | :unknown
  @type decision ::
          :available | {:unavailable, [String.t()]} | {:unknown, [String.t()]} | :suspended

  @doc """
  Decides a part. `part` has `:name`, `:path` and `:gates`. A suspension is decided first, before
  any gate; then every gate down the path must hold.

  Returns `{:ok, decision}` or `{:error, reason}` when the decision cannot be made.
  """
  @spec decide(map(), map()) :: {:ok, decision()} | {:error, term()}
  def decide(part, env) do
    if Enum.any?(Map.get(env, :suspended, []), &suspended?(&1, part)) do
      {:ok, :suspended}
    else
      state = %{cache: %{}, env: env}

      try do
        {outcome, causes, _state} = all(part.gates, state, [])

        case outcome do
          :available -> {:ok, :available}
          :unavailable -> {:ok, {:unavailable, causes}}
          :unknown -> {:ok, {:unknown, causes}}
        end
      catch
        {:availability_failure, reason} -> {:error, reason}
      end
    end
  end

  # A part is also suspended with the container it belongs to (the module of a query).
  defp suspended?(path, part) do
    Paths.covers?(path, part.path, part.name) or
      (Map.has_key?(part, :owner) and Paths.covers?(path, part.owner_path, part.owner))
  end

  @doc "Whether a decision lets the request through."
  @spec available?(decision()) :: boolean()
  def available?(:available), do: true
  def available?(_decision), do: false

  defp eval(%{"kind" => "for", "audience" => audience}, state, _chain) do
    cause = "for " <> audience

    case audiences(state) do
      {:undecided, state} ->
        {:unknown, [cause], state}

      {held, state} ->
        if MapSet.member?(held, audience),
          do: {:available, [], state},
          else: {:unavailable, [cause], state}
    end
  end

  defp eval(%{"kind" => "not", "audience" => audience}, state, _chain) do
    cause = "not " <> audience

    case audiences(state) do
      {:undecided, state} ->
        {:unknown, [cause], state}

      {held, state} ->
        if MapSet.member?(held, audience),
          do: {:unavailable, [cause], state},
          else: {:available, [], state}
    end
  end

  defp eval(%{"kind" => "when", "condition" => condition}, state, _chain) do
    {outcome, state} = condition(condition, state)
    {outcome, if(outcome == :available, do: [], else: ["when " <> describe(condition)]), state}
  end

  defp eval(%{"kind" => "with", "block" => name}, state, chain) do
    cond do
      name in chain ->
        throw({:availability_failure, {:circular_block, Enum.reverse([name | chain])}})

      gate = Map.get(state.env[:blocks] || %{}, name) ->
        eval(gate, state, [name | chain])

      true ->
        {:unknown, ["with " <> name], state}
    end
  end

  defp eval(%{"kind" => "all", "items" => items}, state, chain), do: all(items, state, chain)
  defp eval(%{"kind" => "any", "items" => items}, state, chain), do: any(items, state, chain)
  defp eval(other, state, _chain), do: {:unknown, [inspect(other)], state}

  # All hold: unavailable as soon as one is, otherwise unknown when any is. An empty `all` holds.
  defp all(items, state, chain) do
    {outcome, causes, state} =
      Enum.reduce_while(items, {:available, [], state}, fn item, {acc, causes, state} ->
        case eval(item, state, chain) do
          {:unavailable, c, state} -> {:halt, {:unavailable, c, state}}
          {:unknown, c, state} -> {:cont, {:unknown, causes ++ c, state}}
          {:available, _c, state} -> {:cont, {acc, causes, state}}
        end
      end)

    {outcome, causes, state}
  end

  # Any holds: available as soon as one is, otherwise unknown when any is. An empty `any` holds nothing.
  defp any(items, state, chain) do
    Enum.reduce_while(items, {:unavailable, [], state}, fn item, {acc, causes, state} ->
      case eval(item, state, chain) do
        {:available, _c, state} -> {:halt, {:available, [], state}}
        {:unknown, c, state} -> {:cont, {:unknown, causes ++ c, state}}
        {:unavailable, c, state} -> {:cont, {acc, causes ++ c, state}}
      end
    end)
  end

  defp condition(%{"kind" => "all", "items" => items}, state) do
    Enum.reduce_while(items, {:available, state}, fn item, {acc, state} ->
      case condition(item, state) do
        {:unavailable, state} -> {:halt, {:unavailable, state}}
        {:unknown, state} -> {:cont, {:unknown, state}}
        {:available, state} -> {:cont, {acc, state}}
      end
    end)
  end

  defp condition(%{"kind" => "any", "items" => items}, state) do
    Enum.reduce_while(items, {:unavailable, state}, fn item, {acc, state} ->
      case condition(item, state) do
        {:available, state} -> {:halt, {:available, state}}
        {:unknown, state} -> {:cont, {:unknown, state}}
        {:unavailable, state} -> {:cont, {acc, state}}
      end
    end)
  end

  defp condition(%{"kind" => "compare"} = compare, state) do
    case read(compare["path"], state) do
      {:absent, state} -> {:unknown, state}
      {{:ok, value}, state} -> {compare(compare["operator"], value, compare["operands"]), state}
    end
  end

  defp condition(%{"kind" => "named", "name" => name}, state) do
    case Map.get(state.env[:conditions] || %{}, name) do
      nil ->
        {:unknown, state}

      module ->
        read = fn path ->
          case read(path, state) do
            {:absent, _} -> :absent
            {found, _} -> found
          end
        end

        {module.evaluate(read), state}
    end
  end

  defp condition(_other, state), do: {:unknown, state}

  defp compare("isTrue", value, _), do: bool(value === true)
  defp compare("equal", value, [operand | _]), do: bool(equal?(value, operand))
  defp compare("notEqual", value, [operand | _]), do: bool(not equal?(value, operand))
  defp compare("in", value, operands), do: bool(Enum.any?(operands, &equal?(value, &1)))
  defp compare("notIn", value, operands), do: bool(not Enum.any?(operands, &equal?(value, &1)))
  defp compare("greaterThan", value, [operand | _]), do: order(value, operand, &(&1 > &2))
  defp compare("greaterThanOrEqual", value, [operand | _]), do: order(value, operand, &(&1 >= &2))
  defp compare("lessThan", value, [operand | _]), do: order(value, operand, &(&1 < &2))
  defp compare("lessThanOrEqual", value, [operand | _]), do: order(value, operand, &(&1 <= &2))
  defp compare(_operator, _value, _operands), do: :unknown

  defp bool(true), do: :available
  defp bool(false), do: :unavailable

  # Numbers compare by value whatever their representation; everything else must be the same term.
  defp equal?(a, b) when is_number(a) and is_number(b), do: a == b
  defp equal?(a, b), do: a === b

  defp order(a, b, fun) when is_number(a) and is_number(b), do: bool(fun.(a, b))
  defp order(a, b, fun) when is_binary(a) and is_binary(b), do: bool(fun.(a, b))
  # A value that cannot be ordered against the operand cannot open the gate.
  defp order(_a, _b, _fun), do: :unknown

  defp describe(%{"kind" => "compare", "path" => path, "operator" => "isTrue"}), do: path

  defp describe(%{"kind" => "compare", "path" => path, "operator" => op, "operands" => operands}),
    do: "#{path} #{op} #{Enum.join(operands, ", ")}"

  defp describe(%{"kind" => "named", "name" => name}), do: name

  defp describe(%{"kind" => kind, "items" => items}),
    do: "#{kind}(" <> Enum.map_join(items, ", ", &describe/1) <> ")"

  defp describe(other), do: inspect(other)

  # The audiences are read at most once per decision.
  defp audiences(%{cache: %{audiences: held}} = state), do: {held, state}

  defp audiences(%{env: env} = state) do
    held =
      case env[:audiences] do
        nil ->
          MapSet.new()

        fun ->
          case fun.() do
            {:ok, names} -> MapSet.new(names)
            :undecided -> :undecided
            {:error, reason} -> throw({:availability_failure, reason})
          end
      end

    {held, %{state | cache: Map.put(state.cache, :audiences, held)}}
  end

  # `tenant`, `identity.user`, `arguments.name` and `name.path`: the head is the ambient value or a
  # provided one (read once), the rest navigates maps by key.
  defp read(path, state) do
    [head | rest] = String.split(String.replace_prefix(path, "$context.", ""), ".")
    {value, state} = head(head, state)

    case value do
      :absent -> {:absent, state}
      {:ok, found} -> {navigate(found, rest), state}
    end
  end

  defp head(name, state) do
    ambient = state.env[:ambient] || %{}

    cond do
      Map.has_key?(ambient, name) ->
        {{:ok, Map.fetch!(ambient, name)}, state}

      Map.has_key?(state.cache, {:value, name}) ->
        {Map.fetch!(state.cache, {:value, name}), state}

      provider = Map.get(state.env[:values] || %{}, name) ->
        found =
          case provider.(ambient) do
            {:ok, _} = ok -> ok
            :absent -> :absent
            {:error, reason} -> throw({:availability_failure, reason})
          end

        {found, %{state | cache: Map.put(state.cache, {:value, name}, found)}}

      true ->
        {:absent, state}
    end
  end

  defp navigate(value, []), do: {:ok, value}

  defp navigate(map, [segment | rest]) when is_map(map) do
    case fetch(map, segment) do
      {:ok, next} -> navigate(next, rest)
      :error -> :absent
    end
  end

  defp navigate(_value, _rest), do: :absent

  defp fetch(map, segment) do
    case Map.fetch(map, segment) do
      {:ok, _} = found -> found
      :error -> fetch_atom(map, segment)
    end
  end

  defp fetch_atom(map, segment) do
    Enum.find_value(map, :error, fn
      {key, value} when is_atom(key) ->
        if String.downcase(Atom.to_string(key)) == String.downcase(segment), do: {:ok, value}

      {key, value} when is_binary(key) ->
        if String.downcase(key) == String.downcase(segment), do: {:ok, value}

      _ ->
        nil
    end)
  end
end
