# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Chronicle do
  @moduledoc """
  Appends the events a command returned to Chronicle.

  Events are grouped by event source id, in the order returned, and each group is appended
  atomically (`Chronicle.append_with_result/3` for one event, `append_many_with_result/3` for several). Constraint and concurrency violations
  become validation results (`"constraintViolation"`, `"concurrencyViolation"`) so a client can
  show them like any other rejection.
  """

  require Logger

  alias Arc.{Context, Validation}
  alias Chronicle.EventSequences.AppendResult

  @doc """
  Appends `events` for a command whose key is `default_source`.

  Returns `:ok` or `{:error, results}`.
  """
  @spec append(term(), String.t() | nil, Context.t()) ::
          :ok | {:error, [Arc.ValidationResult.t()]}
  def append(events, default_source, %Context{} = ctx) do
    events
    |> List.wrap()
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case target(event, default_source) do
        {:ok, pair} -> {:cont, {:ok, [pair | acc]}}
        :error -> {:halt, :no_source}
      end
    end)
    |> case do
      :no_source ->
        {:error,
         [
           Validation.error(
             "The command returned an event but declares no key field and gave no event source id.",
             [],
             reason: "frameworkFailure"
           )
         ]}

      {:ok, pairs} ->
        pairs |> Enum.reverse() |> group() |> append_groups(ctx)
    end
  end

  defp target({source, event}, _default) when is_struct(event),
    do: {:ok, {source_id(source), event}}

  defp target(event, nil) when is_struct(event), do: :error
  defp target(event, default) when is_struct(event), do: {:ok, {default, event}}

  defp group(pairs) do
    pairs
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn chunk -> {elem(hd(chunk), 0), Enum.map(chunk, &elem(&1, 1))} end)
  end

  defp append_groups(groups, ctx) do
    Enum.reduce_while(groups, :ok, fn {source, events}, :ok ->
      case append_group(source, events, options(ctx)) do
        {:ok, _result} -> {:cont, :ok}
        {:error, %AppendResult{} = result} -> {:halt, {:error, violations(result)}}
        {:error, reason} -> {:halt, {:error, [failure(reason)]}}
      end
    end)
  end

  # A single event takes the single-event path; several append atomically in one call.
  defp append_group(source, [event], opts), do: Chronicle.append_with_result(source, event, opts)

  defp append_group(source, events, opts),
    do: Chronicle.append_many_with_result(source, events, opts)

  @doc false
  @spec options(Arc.Context.t()) :: keyword()
  def options(ctx) do
    base = [correlation_id: ctx.correlation_id]

    identity =
      case ctx.principal do
        %{authenticated?: true, actor: %{id: actor_id, name: actor_name}, id: id, name: name} ->
          [
            identity:
              Chronicle.Identity.new(
                actor_id,
                actor_name || actor_id,
                "",
                Chronicle.Identity.new(id, name || id)
              )
          ]

        %{authenticated?: true, id: id, name: name} ->
          [identity: Chronicle.Identity.new(id, name || id)]

        _ ->
          []
      end

    ctx.chronicle ++ base ++ identity
  end

  defp violations(%AppendResult{} = result) do
    constraint =
      for v <- result.constraint_violations do
        Validation.error(v.message, [],
          reason: "constraintViolation",
          reason_detail: v.constraint_name
        )
      end

    concurrency =
      for v <- result.concurrency_violations do
        Validation.error(
          "The event source '#{v.event_source_id}' changed since it was read.",
          [],
          reason: "concurrencyViolation"
        )
      end

    other = for e <- result.errors, do: Validation.error(e, [], reason: "frameworkFailure")

    case constraint ++ concurrency ++ other do
      [] -> [Validation.error("Chronicle rejected the append.", [], reason: "frameworkFailure")]
      list -> list
    end
  end

  defp failure(reason) do
    Logger.error("Arc could not append events to Chronicle: #{inspect(reason)}")
    Validation.error("The events could not be recorded.", [], reason: "frameworkFailure")
  end

  @doc false
  @spec source_id(term()) :: String.t()
  def source_id(%{value: value}), do: source_id(value)
  def source_id(value) when is_binary(value), do: value
  def source_id(value), do: to_string(value)
end
