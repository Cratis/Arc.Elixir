# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ArcFixtures.Web.AuthorsLive do
  use Phoenix.LiveView
  use Arc.LiveView, application: ArcFixtures.App

  alias ArcFixtures.Authors.Listing.Authors
  alias ArcFixtures.Authors.Registration.{RegisterAuthor, RenameAuthor}

  def mount(_params, session, socket) do
    socket =
      case session["user"] do
        nil -> socket
        user -> assign(socket, :current_user, user)
      end

    {:ok,
     socket
     |> assign(:renamed, nil)
     |> assign_observable(:authors, Authors, :live_authors)
     |> assign_form(:form, RegisterAuthor, %{"id" => "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"})}
  end

  def handle_event("validate", %{"command" => params}, socket),
    do: {:noreply, validate_form(socket, :form, params)}

  def handle_event("save", %{"command" => params}, socket) do
    case submit_form(socket, :form, params) do
      {:ok, _result, socket} -> {:noreply, assign(socket, :saved, true)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("rename", _params, socket) do
    outcome =
      case execute(socket, %RenameAuthor{
             id: "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e",
             name: "Renamed"
           }) do
        {:ok, result} -> {:ok, result.response}
        {:error, result} -> {:denied, result.authorization_failure_reason}
      end

    {:noreply, assign(socket, :renamed, outcome)}
  end

  def render(assigns) do
    ~H"""
    <ul id="authors">
      <li :for={author <- @authors} id={"author-#{author.id}"}>{author.name}</li>
    </ul>
    <.form for={@form} id="register" phx-change="validate" phx-submit="save">
      <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
      <input type="text" name={@form[:name].name} value={@form[:name].value} id="name" />
      <p :for={{msg, _} <- @form[:name].errors} class="error">{msg}</p>
      <p :for={{:base, {msg, _}} <- @form.errors} class="base-error">{msg}</p>
    </.form>
    <p :if={assigns[:saved]} id="saved">saved</p>
    <button phx-click="rename" id="rename">rename</button>
    <p :if={@renamed} id="renamed">{inspect(@renamed)}</p>
    """
  end
end

defmodule ArcFixtures.Web.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, false)
  end

  scope "/" do
    pipe_through(:browser)
    live("/authors", ArcFixtures.Web.AuthorsLive)
  end
end

defmodule ArcFixtures.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :cratis_arc

  @session_options [
    store: :cookie,
    key: "_arc_fixture",
    signing_salt: "arc-fixture-salt",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Session, @session_options)
  plug(Arc.Plug, application: ArcFixtures.App)
  plug(ArcFixtures.Web.Router)
end

defmodule ArcFixtures.Web.ErrorView do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
