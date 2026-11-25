# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Development do
  @moduledoc """
  What a developer switched on or off while the application runs, to see how it behaves: audiences
  every caller is treated as holding or not holding, and modules, features and slices that are
  available whatever their gates say or not available at all. A tool such as Lens drives it through
  `GET /.cratis/availability/model` and `POST /.cratis/availability/overrides`.

  It is only active in development: `development_tools: :auto` (the default of the availability
  configuration) is on under Mix in `:dev`, and `true` or `false` decides it outright. When it is not
  active the routes are not served and the overrides are never applied. The overrides apply to the
  whole application, not to one caller.

      config :my_app, MyApp.Arc, availability: [development_tools: true]

  The overrides are:

    * `"enabledAudiences"` - audiences every caller holds
    * `"disabledAudiences"` - audiences no caller holds. Wins over the enabled ones
    * `"enabledPaths"` - paths (`"Fleet/Billing"`) available whatever their gates say
    * `"disabledPaths"` - paths that are not available. Wins over the enabled ones

  A path covers everything beneath it, see `Cratis.Arc.Structure`. Changing the overrides tells the
  application, so open observers of `/.cratis/availability` decide again.
  """

  alias Cratis.Arc.Structure

  @none %{
    "enabledAudiences" => [],
    "disabledAudiences" => [],
    "enabledPaths" => [],
    "disabledPaths" => []
  }

  @doc "Overrides that change nothing."
  @spec none() :: map()
  def none, do: @none

  @doc "Whether the application allows overrides."
  @spec active?(module()) :: boolean()
  def active?(app) do
    case app |> Cratis.Arc.Availability.config() |> option() do
      :auto -> Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :dev
      value -> value == true
    end
  end

  defp option(nil), do: false
  defp option(config), do: Keyword.get(config, :development_tools, :auto)

  @doc "The overrides in force. Always none when overrides are not active."
  @spec current(module()) :: map()
  def current(app) do
    if active?(app), do: :persistent_term.get({__MODULE__, app}, @none), else: @none
  end

  @doc """
  Replaces the overrides and tells the application. Returns `{:error, :inactive}` when overrides
  are not active.
  """
  @spec apply_overrides(module(), map()) :: {:ok, map()} | {:error, :inactive}
  def apply_overrides(app, overrides) do
    if active?(app) do
      normalized = normalize(overrides)
      :persistent_term.put({__MODULE__, app}, normalized)
      Cratis.Arc.Availability.changed(app)
      {:ok, normalized}
    else
      {:error, :inactive}
    end
  end

  @doc "Removes every override."
  @spec reset(module()) :: :ok
  def reset(app) do
    :persistent_term.erase({__MODULE__, app})
    Cratis.Arc.Availability.changed(app)
    :ok
  end

  @doc "Cleans overrides: unknown keys dropped, blanks and duplicates removed, every list sorted."
  @spec normalize(term()) :: map()
  def normalize(%{} = overrides) do
    Map.new(@none, fn {key, _} -> {key, clean(Map.get(overrides, key))} end)
  end

  def normalize(_other), do: @none

  defp clean(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp clean(_other), do: []

  @doc """
  What the overrides say about a part: `:off` (switched off), `:on` (switched on) or `:none`.
  Off wins over on.
  """
  @spec switch(map(), map()) :: :off | :on | :none
  def switch(overrides, part) do
    segments = Structure.location_segments(part.module, part.feature, part.slice)

    cond do
      Enum.any?(overrides["disabledPaths"], &Structure.within?(segments, &1)) -> :off
      Enum.any?(overrides["enabledPaths"], &Structure.within?(segments, &1)) -> :on
      true -> :none
    end
  end

  @doc "The audiences a caller holds once the overrides are applied to what it really holds."
  @spec audiences(map(), [String.t()]) :: [String.t()]
  def audiences(overrides, held) do
    ((held ++ overrides["enabledAudiences"]) |> Enum.uniq()) -- overrides["disabledAudiences"]
  end
end
