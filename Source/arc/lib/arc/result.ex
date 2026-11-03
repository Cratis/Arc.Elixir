# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.CommandResult do
  @moduledoc """
  The outcome of executing a command, shaped as the Arc command result envelope.
  """

  defstruct correlation_id: nil,
            authorized?: true,
            validation_results: [],
            exception_messages: [],
            exception_stack_trace: "",
            authorization_failure_reason: "",
            response: nil,
            events: []

  @type t :: %__MODULE__{}

  @doc "Whether the command was authorized, valid and free of exceptions."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{} = r),
    do: r.authorized? and r.validation_results == [] and r.exception_messages == []

  @doc "The HTTP status the Arc contract maps this result to."
  @spec status(t()) :: 200 | 400 | 403 | 500
  def status(%__MODULE__{} = r) do
    cond do
      success?(r) -> 200
      not r.authorized? -> 403
      r.validation_results != [] -> 400
      true -> 500
    end
  end

  @doc "Converts the result to the wire envelope."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = r) do
    base = %{
      "correlationId" => r.correlation_id,
      "isAuthorized" => r.authorized?,
      "isValid" => r.validation_results == [],
      "isSuccess" => success?(r),
      "hasExceptions" => r.exception_messages != [],
      "validationResults" => Enum.map(r.validation_results, &Arc.ValidationResult.to_wire/1),
      "exceptionMessages" => r.exception_messages,
      "exceptionStackTrace" => r.exception_stack_trace,
      "authorizationFailureReason" => r.authorization_failure_reason
    }

    if success?(r) and r.response != nil,
      do: Map.put(base, "response", Arc.Wire.encode(r.response)),
      else: base
  end
end

defmodule Arc.QueryResult do
  @moduledoc """
  The outcome of executing a query, shaped as the Arc query result envelope.
  """

  defstruct correlation_id: nil,
            data: nil,
            ready?: true,
            authorized?: true,
            validation_results: [],
            exception_messages: [],
            exception_stack_trace: "",
            paging: %{page: 0, size: 0, total_items: 0}

  @type t :: %__MODULE__{}

  @doc "Whether the query was ready, authorized, valid and free of exceptions."
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{} = r),
    do: r.ready? and r.authorized? and r.validation_results == [] and r.exception_messages == []

  @doc "The HTTP status the Arc contract maps this result to."
  @spec status(t()) :: 200 | 202 | 400 | 403 | 500
  def status(%__MODULE__{} = r) do
    cond do
      success?(r) -> 200
      not r.authorized? -> 403
      r.validation_results != [] -> 400
      not r.ready? and r.exception_messages == [] -> 202
      true -> 500
    end
  end

  @doc "Converts the result to the wire envelope."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = r) do
    %{page: page, size: size, total_items: total} = r.paging

    base = %{
      "correlationId" => r.correlation_id,
      "isReady" => r.ready?,
      "isAuthorized" => r.authorized?,
      "isValid" => r.validation_results == [],
      "isSuccess" => success?(r),
      "hasExceptions" => r.exception_messages != [],
      "validationResults" => Enum.map(r.validation_results, &Arc.ValidationResult.to_wire/1),
      "exceptionMessages" => r.exception_messages,
      "exceptionStackTrace" => r.exception_stack_trace,
      "paging" => %{
        "page" => page,
        "size" => size,
        "totalItems" => total,
        "totalPages" => if(size == 0, do: 0, else: ceil(total / size))
      }
    }

    if success?(r) and r.data != nil,
      do: Map.put(base, "data", Arc.Wire.encode(r.data)),
      else: base
  end
end
