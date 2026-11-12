# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Config do
  @moduledoc """
  The analyzer's configuration.

      # config/config.exs
      config :cratis_arc, :analyzer,
        enabled: true,
        segments_to_skip: 1,
        rules: [
          {"ARCE0001", :error},
          {"ARCE0003", :off}
        ]

    * `:enabled` - `false` switches the whole analyzer off. Defaults to `true`.
    * `:rules` - the severity per rule id: `:error`, `:warning`, `:info` or `:off`. A rule
      that is not listed keeps its default severity. A keyword list or a map works as well as
      a list of `{id, severity}` tuples.
    * `:segments_to_skip` - the same value as the `segments_to_skip` of `use Arc.Application`
      (default `1`), so `ARCE0005` computes the routes your application serves.

  `mix compile --warnings-as-errors` fails on `:warning` findings the same way it does for
  compiler warnings.
  """

  alias Arc.Analyzer.Rules

  @severities [:error, :warning, :info, :off]

  defstruct enabled: true, severities: %{}, segments_to_skip: 1

  @type t :: %__MODULE__{
          enabled: boolean(),
          severities: %{String.t() => atom()},
          segments_to_skip: non_neg_integer()
        }

  @doc "Reads the configuration from the application environment."
  @spec load() :: t()
  def load, do: from(Application.get_env(:cratis_arc, :analyzer, []))

  @doc "Builds the configuration from the `:analyzer` options."
  @spec from(keyword() | map()) :: t()
  def from(options) do
    options = Map.new(options)

    %__MODULE__{
      enabled: Map.get(options, :enabled, true) != false,
      severities:
        options
        |> Map.get(:rules, [])
        |> Enum.map(fn {id, sev} -> {to_string(id), sev} end)
        |> Map.new(),
      segments_to_skip: Map.get(options, :segments_to_skip, 1)
    }
  end

  @doc """
  The problems with the configuration, as human-readable messages: a rule id that does not
  exist, or a severity that is not one of `:error`, `:warning`, `:info`, `:off`.
  """
  @spec problems(t()) :: [String.t()]
  def problems(%__MODULE__{severities: severities}) do
    known = Rules.all() |> Enum.map(& &1.id()) |> MapSet.new()

    Enum.flat_map(severities, fn {id, severity} ->
      cond do
        id not in known -> ["unknown rule #{inspect(id)} in config :cratis_arc, :analyzer"]
        severity not in @severities -> ["rule #{id} has invalid severity #{inspect(severity)}"]
        true -> []
      end
    end)
  end

  @doc "The severity in effect for `rule`: the configured one, else the rule's default."
  @spec severity(t(), module()) :: Arc.Analyzer.Rule.severity()
  def severity(%__MODULE__{severities: severities}, rule) do
    case Map.get(severities, rule.id()) do
      severity when severity in @severities -> severity
      _ -> rule.default_severity()
    end
  end
end
