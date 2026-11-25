# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Cratis.Arc.LiveView.Availability do
    @moduledoc """
    A function component that hides the parts of a page the caller cannot use.

        <Cratis.Arc.LiveView.Availability.available
          socket={@socket}
          version={@arc_availability}
          command={MyApp.Fleet.Vessels.DockVessel}
          arguments={%{"vesselId" => @vessel.id}}
        >
          <button phx-click="dock">Dock</button>
          <:unavailable>Docking is not part of your plan.</:unavailable>
        </Cratis.Arc.LiveView.Availability.available>

    It asks `Cratis.Arc.LiveView.available?/3`, so the same gate that decides an execution decides what is
    shown; nothing is decided twice. Hiding is presentation: the server refuses regardless.

    Pass `version={@arc_availability}`: a connected LiveView counts every change of audiences and
    suspensions in that assign, which re-renders what the component shows.

    Attributes: `socket`, `command` (a command module) or `query` (`{read_model, query_name}`),
    `arguments` (what the part is about) and `version`.
    """

    use Phoenix.Component

    attr(:socket, :any, required: true)
    attr(:command, :atom, default: nil)
    attr(:query, :any, default: nil)
    attr(:arguments, :map, default: %{})
    attr(:version, :integer, default: 0)
    slot(:inner_block, required: true)
    slot(:unavailable)

    @doc "Renders the inner block when the part is available, the `:unavailable` slot otherwise."
    def available(assigns) do
      part = assigns.command || assigns.query

      assigns =
        assign(
          assigns,
          :show?,
          Cratis.Arc.LiveView.available?(assigns.socket, part, assigns.arguments)
        )

      ~H"""
      <%= if @show? do %>
        {render_slot(@inner_block)}
      <% else %>
        {render_slot(@unavailable)}
      <% end %>
      """
    end
  end
end
