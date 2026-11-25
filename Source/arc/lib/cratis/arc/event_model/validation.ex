# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.EventModel.Validation do
  @moduledoc false

  # Checks that an event model tells a whole story, so the board never shows an empty or a dangling
  # slice: a state change has a command and the events it appends, a view has a read model and the
  # events it consumes, an automation has the event it reacts to and the facts it records, every
  # consumed event is produced by a slice, and a fact is drawn before whatever uses it.

  @doc "The problems of the slices (in reading order) as `\"Module/Feature/Slice: what is wrong\"` strings."
  @spec check([map()]) :: [String.t()]
  def check(slices) do
    positions = slices |> Enum.with_index() |> Map.new(fn {s, i} -> {s.key, i} end)

    for {slice, index} <- Enum.with_index(slices),
        problem <- problems(slice, index, positions) do
      "#{label(slice)}: #{problem}"
    end
  end

  defp problems(%{type: 0} = slice, _index, _positions) do
    List.flatten([
      if(slice.commands == [], do: ["a state change without a command"], else: []),
      if(slice.events == [], do: ["its command appends no events"], else: [])
    ])
  end

  defp problems(%{type: 1} = slice, index, positions) do
    List.flatten([
      if(is_nil(slice.model), do: ["a view without a read model"], else: []),
      if(slice.events ++ slice.external == [],
        do: ["a view that consumes no events (declare `consumes:` on the read model)"],
        else: []
      ),
      for(
        event <- slice.events,
        event.owner == slice.key,
        do: "#{event.name} is declared here but no command appends it"
      ),
      consumed(slice, index, positions)
    ])
  end

  defp problems(%{type: 2} = slice, index, positions) do
    List.flatten([
      if(slice.external == [], do: ["an automation that reacts to no event"], else: []),
      if(slice.events == [], do: ["an automation that records no event"], else: []),
      consumed(slice, index, positions)
    ])
  end

  defp problems(_slice, _index, _positions), do: []

  defp consumed(slice, index, positions) do
    for event <- slice.external do
      case event.owner do
        nil ->
          "consumes #{event.name}, which no slice produces"

        owner when owner == slice.key ->
          []

        owner ->
          if Map.get(positions, owner, -1) > index,
            do:
              "consumes #{event.name} before #{owner |> Enum.reject(&(&1 == "")) |> Enum.join("/")} produces it",
            else: []
      end
    end
  end

  defp label(slice),
    do: [slice.module, slice.feature, slice.name] |> Enum.reject(&(&1 == "")) |> Enum.join("/")
end
