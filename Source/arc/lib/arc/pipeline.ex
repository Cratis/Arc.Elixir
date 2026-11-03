# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Pipeline do
  @moduledoc """
  Runs commands and queries: authorize, bind, validate, provide, handle, record.

  This is what the HTTP host, LiveView, `Arc.Test` and `Arc.execute/3` all call, so a rule is
  implemented once and holds on every path.

  Telemetry events are emitted around each run:

    * `[:arc, :command, :start | :stop]` with `%{command: module, correlation_id: id}` (stop adds `success?`)
    * `[:arc, :query, :start | :stop]` with `%{read_model: module, query: name, correlation_id: id}`
  """

  require Logger

  alias Arc.{Context, CommandResult, QueryResult, Validation}
  alias Arc.Descriptor.Query

  @generic_message "An unexpected error occurred. See the server logs using the correlation id."

  @doc """
  Executes a command.

  `input` is a wire map (string keys, `camelCase`) or an already-built command struct.

  ## Options

    * `:validate_only` - authorize and validate, but do not provide or handle
  """
  @spec execute_command(module(), map() | struct(), Context.t(), keyword()) :: CommandResult.t()
  def execute_command(command_module, input, %Context{} = ctx, opts \\ []) do
    meta = %{command: command_module, correlation_id: ctx.correlation_id}

    :telemetry.span([:arc, :command], meta, fn ->
      result = run_command(command_module, input, ctx, opts)
      {result, Map.put(meta, :success?, CommandResult.success?(result))}
    end)
  end

  defp run_command(module, input, ctx, opts) do
    base = %CommandResult{correlation_id: ctx.correlation_id}
    descriptor = module.__arc__()

    with_logger_metadata(ctx, fn ->
      with {:ok, command} <- bind_command(module, input, base),
           :ok <- authorize(descriptor.authorization, ctx, command, base),
           :ok <- validate_command(module, descriptor, command, ctx, base) do
        if opts[:validate_only],
          do: base,
          else: provide_and_handle(module, descriptor, command, ctx, base)
      else
        {:halt, result} -> result
      end
    end)
  rescue
    exception -> exception_result(exception, __STACKTRACE__, ctx)
  end

  defp bind_command(_module, %{__struct__: _} = command, _base), do: {:ok, command}

  defp bind_command(module, wire, base) when is_map(wire) do
    case Arc.Schema.cast(module, wire) do
      {:ok, command} -> {:ok, command}
      {:error, results} -> {:halt, %{base | validation_results: results}}
    end
  end

  defp authorize(requirement, ctx, subject, base) do
    case Arc.Authorization.check(requirement, ctx, subject) do
      :ok ->
        :ok

      {:error, :unauthenticated} ->
        {:halt,
         %{base | authorized?: false, authorization_failure_reason: "Authentication is required."}}

      {:error, {:forbidden, reason}} ->
        {:halt, %{base | authorized?: false, authorization_failure_reason: reason}}
    end
  end

  defp validate_command(module, descriptor, command, ctx, base) do
    declared = Validation.validate_fields(command, descriptor.fields)

    custom =
      if function_exported?(module, :validate, 2),
        do: normalize_results(module.validate(command, ctx)),
        else: []

    case filter_severity(declared ++ custom, ctx) do
      [] -> :ok
      results -> {:halt, %{base | validation_results: results}}
    end
  end

  defp provide_and_handle(module, descriptor, command, ctx, base) do
    case provide(module, command, ctx) do
      {:ok, ctx} -> handle(module, descriptor, command, ctx, base)
      {:error, results} -> %{base | validation_results: filter_severity(results, ctx)}
    end
  end

  defp provide(module, command, ctx) do
    if function_exported?(module, :provide, 2) do
      case module.provide(command, ctx) do
        :ok ->
          {:ok, ctx}

        {:ok, provided} when is_map(provided) ->
          {:ok, %{ctx | provided: Map.merge(ctx.provided, provided)}}

        {:error, errors} ->
          {:error, normalize_results({:error, errors})}
      end
    else
      {:ok, ctx}
    end
  end

  defp handle(module, descriptor, command, ctx, base) do
    case module.handle(command, ctx) do
      {:append, events} ->
        record(events, nil, descriptor, command, ctx, base)

      {:append, events, response} ->
        record(events, response, descriptor, command, ctx, base)

      {:ok, response} ->
        %{base | response: response}

      {:error, errors} ->
        %{base | validation_results: filter_severity(normalize_results({:error, errors}), ctx)}

      other ->
        raise ArgumentError,
              "#{inspect(module)}.handle/2 returned #{inspect(other)}; expected {:append, events}, {:append, events, response}, {:ok, response} or {:error, results}"
    end
  end

  defp record(events, response, descriptor, command, ctx, base) do
    default_source =
      case descriptor.key do
        nil -> nil
        key -> command |> Map.get(key) |> key_to_source()
      end

    case Arc.Chronicle.append(events, default_source, ctx) do
      :ok -> %{base | response: response, events: List.wrap(events)}
      {:error, results} -> %{base | validation_results: results}
    end
  end

  defp key_to_source(nil), do: nil
  defp key_to_source(value), do: Arc.Chronicle.source_id(value)

  @doc """
  Executes a query.

  `args` is a map of raw argument values keyed by wire name (matched case-insensitively).

  ## Options

    * `:page`, `:page_size` - zero-based page and page size, applied to lists
    * `:sort_by`, `:sort_direction` - field name (`camelCase`) and `:asc` or `:desc`
  """
  @spec execute_query(Arc.Descriptor.t(), Query.t(), map(), Context.t(), keyword()) ::
          QueryResult.t()
  def execute_query(descriptor, %Query{} = query, args, %Context{} = ctx, opts \\ []) do
    meta = %{read_model: descriptor.module, query: query.name, correlation_id: ctx.correlation_id}

    :telemetry.span([:arc, :query], meta, fn ->
      result = run_query(descriptor, query, args, ctx, opts)
      {result, Map.put(meta, :success?, QueryResult.success?(result))}
    end)
  end

  defp run_query(descriptor, query, raw_args, ctx, opts) do
    base = %QueryResult{correlation_id: ctx.correlation_id}

    with_logger_metadata(ctx, fn ->
      with :ok <- authorize_query(query.authorization, ctx, base),
           {:ok, args} <- bind_arguments(query, raw_args, base) do
        case apply(descriptor.module, query.name, [args, ctx]) do
          {:ok, value} ->
            shape(value, descriptor, query, opts, base)

          {:error, errors} ->
            %{base | validation_results: normalize_results({:error, errors})}

          other ->
            raise ArgumentError,
                  "#{inspect(descriptor.module)}.#{query.name}/2 returned #{inspect(other)}; expected {:ok, value} or {:error, results}"
        end
      else
        {:halt, result} -> result
      end
    end)
  rescue
    exception ->
      cmd = exception_result(exception, __STACKTRACE__, ctx)

      %QueryResult{
        correlation_id: ctx.correlation_id,
        exception_messages: cmd.exception_messages,
        exception_stack_trace: cmd.exception_stack_trace
      }
  end

  defp authorize_query(requirement, ctx, base) do
    case Arc.Authorization.check(requirement, ctx, :query) do
      :ok -> :ok
      {:error, _} -> {:halt, %{base | authorized?: false}}
    end
  end

  defp bind_arguments(query, raw, base) do
    lookup = Map.new(raw, fn {k, v} -> {String.downcase(to_string(k)), v} end)

    {args, errors} =
      Enum.reduce(query.params, {%{}, []}, fn param, {args, errors} ->
        wire = param.name |> Arc.Naming.camel() |> String.downcase()

        case Map.fetch(lookup, wire) do
          :error ->
            if param.required?,
              do: {args, [missing(param) | errors]},
              else: {Map.put(args, param.name, nil), errors}

          {:ok, value} ->
            case Arc.Types.cast(param.type, value) do
              {:ok, casted} -> {Map.put(args, param.name, casted), errors}
              :error -> {args, [malformed(param) | errors]}
            end
        end
      end)

    if errors == [],
      do: {:ok, args},
      else: {:halt, %{base | validation_results: Enum.reverse(errors)}}
  end

  defp missing(param),
    do:
      Validation.error(
        "The argument '#{Arc.Naming.camel(param.name)}' is required.",
        [param.name],
        reason: "malformedRequest"
      )

  defp malformed(param),
    do:
      Validation.error(
        "The argument '#{Arc.Naming.camel(param.name)}' is not a valid #{Arc.Types.describe(param.type)}.",
        [param.name],
        reason: "malformedRequest"
      )

  defp shape(%Arc.Page{} = page, _descriptor, _query, _opts, base),
    do: %{
      base
      | data: page.items,
        paging: %{page: page.page, size: page.size, total_items: page.total}
    }

  defp shape(list, descriptor, query, opts, base) when is_list(list) and query.many? do
    total = length(list)
    sorted = sort(list, descriptor, opts)

    case opts[:page_size] do
      size when is_integer(size) and size > 0 ->
        page = opts[:page] || 0
        items = sorted |> Enum.drop(page * size) |> Enum.take(size)
        %{base | data: items, paging: %{page: page, size: size, total_items: total}}

      _ ->
        %{base | data: sorted, paging: %{page: 0, size: 0, total_items: total}}
    end
  end

  defp shape(value, _descriptor, _query, _opts, base), do: %{base | data: value}

  defp sort(list, descriptor, opts) do
    with sort_by when is_binary(sort_by) <- opts[:sort_by],
         field when not is_nil(field) <- sort_field(descriptor, sort_by) do
      direction = opts[:sort_direction] || :asc
      Enum.sort_by(list, &sort_key(&1, field), direction)
    else
      _ -> list
    end
  end

  defp sort_field(descriptor, sort_by) do
    descriptor.model
    |> Arc.Schema.model_fields()
    |> Enum.find_value(fn f -> if Arc.Naming.camel(f.name) == sort_by, do: f.name end)
  end

  defp sort_key(item, field) do
    case Map.get(item, field) do
      %{value: v} -> v
      v -> v
    end
  end

  defp normalize_results(:ok), do: []
  defp normalize_results({:error, %Arc.ValidationResult{} = r}), do: [r]
  defp normalize_results({:error, list}) when is_list(list), do: list

  defp normalize_results({:error, other}) do
    Logger.warning(
      "Arc artifact returned an error that is not a validation result: #{inspect(other)}"
    )

    [Validation.error("The request could not be completed.", [], reason: "frameworkFailure")]
  end

  defp filter_severity(results, %Context{allowed_severity: allowed}),
    do: Enum.reject(results, &(Arc.ValidationResult.severity_value(&1.severity) <= allowed))

  defp exception_result(exception, stacktrace, ctx) do
    Logger.error(
      "Arc artifact raised: " <> Exception.format(:error, exception, stacktrace),
      arc_correlation_id: ctx.correlation_id
    )

    expose? =
      case ctx.application do
        nil -> true
        app -> Arc.Application.state(app).config[:expose_exceptions]
      end

    {message, trace} =
      if expose?,
        do: {Exception.message(exception), Exception.format_stacktrace(stacktrace)},
        else: {@generic_message, ""}

    %CommandResult{
      correlation_id: ctx.correlation_id,
      exception_messages: [message],
      exception_stack_trace: trace
    }
  end

  defp with_logger_metadata(ctx, fun) do
    previous = Logger.metadata()
    Logger.metadata(arc_correlation_id: ctx.correlation_id, arc_tenant: ctx.tenant)

    try do
      fun.()
    after
      Logger.reset_metadata(previous)
    end
  end
end
