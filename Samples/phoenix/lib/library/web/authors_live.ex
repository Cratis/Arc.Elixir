# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.AuthorsLive do
  @moduledoc """
  The authors page as LiveView. It calls the same commands and queries as the React app, in
  process: no HTTP, no generated TypeScript.
  """

  use Phoenix.LiveView
  use Arc.LiveView, application: Library.Arc

  alias Library.Authors.Listing.Authors
  alias Library.Authors.Registration.{RegisterAuthor, RenameAuthor}

  def mount(_params, session, socket) do
    # The signed-in user lives in the session; Arc reads the principal from the socket on every call.
    socket = if user = session["user"], do: assign(socket, :current_user, user), else: socket

    {:ok,
     socket
     |> assign(:notice, nil)
     |> assign_observable(:authors, Authors, :live_authors)
     |> new_form()}
  end

  def handle_event("validate", %{"command" => params}, socket),
    do: {:noreply, validate_form(socket, :form, params)}

  def handle_event("register", %{"command" => params}, socket) do
    case submit_form(socket, :form, params) do
      {:ok, _result, socket} -> {:noreply, socket |> new_form() |> assign(:notice, "Registered.")}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("rename", %{"id" => id}, socket) do
    command = %RenameAuthor{id: id, name: "Renamed #{System.unique_integer([:positive])}"}
    {:noreply, assign(socket, :notice, describe(execute(socket, command)))}
  end

  defp describe({:ok, _result}), do: "Renamed."

  defp describe({:error, %{authorized?: false} = result}),
    do: "Not allowed: #{result.authorization_failure_reason}"

  defp describe({:error, _result}), do: "The rename was rejected."

  defp new_form(socket), do: assign_form(socket, :form, RegisterAuthor, %{"id" => Arc.new_id()})

  def render(assigns) do
    ~H"""
    <main>
      <h1>Authors</h1>
      <p :if={@notice} id="notice">{@notice}</p>

      <ul id="authors">
        <li :for={author <- @authors} id={"author-#{author.id}"}>
          {author.name}
          <button phx-click="rename" phx-value-id={author.id}>Rename (editors only)</button>
        </li>
      </ul>

      <.form for={@form} id="register" phx-change="validate" phx-submit="register">
        <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
        <label for="name">Name</label>
        <input type="text" id="name" name={@form[:name].name} value={@form[:name].value} />
        <p :for={{msg, _} <- @form[:name].errors} class="error">{msg}</p>
        <p :for={{:base, {msg, _}} <- @form.errors} class="error">{msg}</p>
        <button type="submit">Register</button>
      </.form>
    </main>
    """
  end
end
