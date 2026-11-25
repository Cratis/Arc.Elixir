# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.AudienceSource do
  @moduledoc """
  Where audience grants come from: the one behaviour to implement over your storage.

  `grants/1` gets the subject (`%{tenant:, user:, application:}`) and returns the names of the
  audiences it holds, from every level (the tenant, the user, the system) together: there is no
  precedence between levels. A grant for an audience the definition does not declare is never
  matched. An error is never a denial: the caller gets a retryable error.

  When grants change, call `Cratis.Arc.Availability.changed/1`.
  """

  @callback grants(subject :: map()) :: {:ok, [String.t()]} | {:error, term()}
end

defmodule Cratis.Arc.Availability.SuspensionSource do
  @moduledoc """
  Where suspensions come from. `suspended/0` returns the suspended paths: a module (`"Fleet"`), a
  feature (`"Fleet/Vessels"`), a slice (`"Fleet/Vessels/Dock"`) or the full name of a part. A
  suspension is decided before any gate, whatever the gates say.

  When suspensions change, call `Cratis.Arc.Availability.changed/1`.
  """

  @callback suspended() :: {:ok, [String.t()]} | {:error, term()}
end

defmodule Cratis.Arc.Availability.Memory do
  @moduledoc """
  An audience source and a suspension source in memory, complete for specifications and samples.
  Start it (`Cratis.Arc.Availability.Memory.start_link(app: MyApp.Arc)`) and configure the module as both
  sources. Every change tells the application, so open observers decide again.

      Cratis.Arc.Availability.Memory.grant({:tenant, "acme"}, "Plus")
      Cratis.Arc.Availability.Memory.withdraw({:tenant, "acme"}, "Plus")
      Cratis.Arc.Availability.Memory.suspend("Fleet/Vessels")
      Cratis.Arc.Availability.Memory.resume("Fleet/Vessels")

  A grant is at a level: `{:tenant, id}`, `{:user, id}` or `:system`. Withdrawing at one level leaves
  the other levels alone.
  """

  @behaviour Cratis.Arc.Availability.AudienceSource
  @behaviour Cratis.Arc.Availability.SuspensionSource

  use Agent

  @doc "Starts the store. `:app` is the application to tell about changes."
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{app: opts[:app], grants: MapSet.new(), suspended: MapSet.new()} end,
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  @doc "Grants an audience at a level."
  @spec grant(term(), String.t()) :: :ok
  def grant(level, audience),
    do: update(&%{&1 | grants: MapSet.put(&1.grants, {level, audience})})

  @doc "Withdraws an audience at a level."
  @spec withdraw(term(), String.t()) :: :ok
  def withdraw(level, audience),
    do: update(&%{&1 | grants: MapSet.delete(&1.grants, {level, audience})})

  @doc "Suspends a path."
  @spec suspend(String.t()) :: :ok
  def suspend(path), do: update(&%{&1 | suspended: MapSet.put(&1.suspended, path)})

  @doc "Resumes a suspended path."
  @spec resume(String.t()) :: :ok
  def resume(path), do: update(&%{&1 | suspended: MapSet.delete(&1.suspended, path)})

  @impl Cratis.Arc.Availability.AudienceSource
  def grants(%{tenant: tenant, user: user}) do
    names =
      for {level, audience} <- Agent.get(__MODULE__, & &1.grants),
          level == :system or level == {:tenant, tenant} or level == {:user, user},
          uniq: true,
          do: audience

    {:ok, names}
  end

  @impl Cratis.Arc.Availability.SuspensionSource
  def suspended, do: {:ok, Agent.get(__MODULE__, &MapSet.to_list(&1.suspended))}

  defp update(fun) do
    app =
      Agent.get_and_update(__MODULE__, fn state ->
        new = fun.(state)
        {new.app, new}
      end)

    if app, do: Cratis.Arc.Availability.changed(app)
    :ok
  end
end

defmodule Cratis.Arc.Availability.Listener do
  @moduledoc false
  # Subscribes this node to the availability changes other nodes broadcast on Phoenix.PubSub and
  # re-runs the observers here.

  use GenServer

  def start_link(app), do: GenServer.start_link(__MODULE__, app)

  @impl true
  def init(app) do
    pubsub = Keyword.fetch!(Cratis.Arc.Availability.config(app), :pubsub)
    :ok = Phoenix.PubSub.subscribe(pubsub, Cratis.Arc.Availability.pubsub_topic(app))
    {:ok, app}
  end

  @impl true
  def handle_info({:arc_availability_changed, app}, app) do
    Cratis.Arc.Notifier.notify(app, Cratis.Arc.Availability.topic())
    {:noreply, app}
  end

  def handle_info(_other, app), do: {:noreply, app}
end
