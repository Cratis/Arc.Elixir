# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Parts do
  @moduledoc """
  The observable `/.cratis/availability` of an application that configured availability.

  It answers `%{"unavailable" => [%{"name", "module", "feature", "slice", "reason"}]}`: what is not
  available to the caller, with the reason `NotAvailable` or `Suspended`. Everything not listed is
  available. It emits the current answer first and again each time audiences or suspensions change.
  `?part=<name>&arguments=<json>` asks about one part and the data it is about. A decision that
  cannot be made is a retryable error, never a list.
  """

  @route "/.cratis/availability"

  @doc false
  def route, do: @route

  @doc false
  def descriptor do
    query = %Cratis.Arc.Descriptor.Query{
      name: :unavailable,
      doc: "What is not available to the caller.",
      params: [
        %Cratis.Arc.Schema.Field{name: :part, type: :string, nullable?: true, required?: false},
        %Cratis.Arc.Schema.Field{
          name: :arguments,
          type: :string,
          nullable?: true,
          required?: false
        }
      ],
      watch: [],
      topics: [Cratis.Arc.Availability.topic()],
      many?: false,
      observable?: true,
      route: @route,
      authorization: Cratis.Arc.Authorization.normalize(allow_anonymous: true)
    }

    %Cratis.Arc.Descriptor{
      kind: :read_model,
      module: __MODULE__,
      name: "Parts",
      namespace: ["Arc", "Availability"],
      doc: "What is not available to the caller.",
      queries: [query],
      authorization: Cratis.Arc.Authorization.normalize(allow_anonymous: true)
    }
  end

  @doc false
  def unavailable(args, ctx) do
    with {:ok, arguments} <- arguments(args[:arguments]),
         {:ok, list} <-
           Cratis.Arc.Availability.unavailable(ctx, part: args[:part], arguments: arguments) do
      {:ok, %{"unavailable" => list}}
    else
      :malformed ->
        {:error,
         [
           %Cratis.Arc.ValidationResult{
             severity: :error,
             message: "The arguments are not a JSON object.",
             members: ["arguments"],
             state: %{}
           }
         ]}

      {:error, _reason} ->
        {:retryable, "The availability could not be decided. Try again."}
    end
  end

  defp arguments(nil), do: {:ok, %{}}
  defp arguments(""), do: {:ok, %{}}

  defp arguments(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> :malformed
    end
  end
end
