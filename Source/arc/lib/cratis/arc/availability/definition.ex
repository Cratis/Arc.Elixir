# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.Availability.Definition do
  @moduledoc """
  The availability vocabulary of an application: its audiences, blocks, scopes and provided values.
  Name it in the application configuration:

      config :my_app, MyApp.Arc, availability: [definition: MyApp.Availability]

      defmodule MyApp.Availability do
        use Cratis.Arc.Availability.Definition

        audience "Plus", "Customers on the Plus package"
        audience "Admin", "Operators"

        block "Paid", "Sold with Plus", for: ["Plus", "Admin"]

        # a gate on a module, a feature or a slice: every artifact below the namespace
        scope "MyApp.Fleet", with: "Paid"

        # a context value, read lazily and once per request
        value "vessel", MyApp.VesselValue
      end

  Gates on a single command or read model are declared on it with `available`.

  A value provider is a module with `value(ambient)`, or a one-argument function. `ambient` holds
  `"tenant"`, `"identity"` and `"arguments"`; it returns `{:ok, value}`, `:absent` or
  `{:error, reason}`. An error is never a denial: the caller gets a retryable error.
  """

  @callback value(ambient :: map()) :: {:ok, term()} | :absent | {:error, term()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Cratis.Arc.Availability.Definition,
        only: [audience: 2, block: 2, block: 3, scope: 2, value: 2, value: 3]

      Module.register_attribute(__MODULE__, :arc_audiences, accumulate: true)
      Module.register_attribute(__MODULE__, :arc_blocks, accumulate: true)
      Module.register_attribute(__MODULE__, :arc_scopes, accumulate: true)
      Module.register_attribute(__MODULE__, :arc_values, accumulate: true)
      @before_compile Cratis.Arc.Availability.Definition
    end
  end

  @doc "Declares an audience, with the description the model carries."
  defmacro audience(name, description \\ "") when is_binary(name) do
    quote do: @arc_audiences({unquote(name), unquote(description)})
  end

  @doc "Declares a reusable block: all of its lines hold."
  defmacro block(name, description \\ "", lines) when is_binary(name) do
    quote do
      @arc_blocks {unquote(name), unquote(description), unquote(lines)}
    end
  end

  @doc "Gates every artifact whose namespace is `namespace` or below it, for example `\"MyApp.Fleet\"`."
  defmacro scope(namespace, lines) when is_binary(namespace) do
    quote do: @arc_scopes({unquote(namespace), unquote(lines)})
  end

  @doc "Declares a context value a `when` can read, by `name`."
  defmacro value(name, provider, opts \\ []) when is_binary(name) do
    quote do: @arc_values({unquote(name), unquote(provider), unquote(opts)})
  end

  @doc false
  defmacro __before_compile__(env) do
    audiences = env.module |> Module.get_attribute(:arc_audiences) |> Enum.reverse()
    blocks = env.module |> Module.get_attribute(:arc_blocks) |> Enum.reverse()
    scopes = env.module |> Module.get_attribute(:arc_scopes) |> Enum.reverse()
    values = env.module |> Module.get_attribute(:arc_values) |> Enum.reverse()

    quote do
      @doc false
      def __availability__ do
        Cratis.Arc.Availability.Definition.build(
          unquote(Macro.escape(audiences)),
          unquote(Macro.escape(blocks)),
          unquote(Macro.escape(scopes)),
          unquote(Macro.escape(values))
        )
      end
    end
  end

  @doc false
  def build(audiences, blocks, scopes, values) do
    %{
      audiences:
        Enum.map(audiences, fn {name, description} ->
          %{"name" => name, "description" => description}
        end),
      blocks:
        Enum.map(blocks, fn {name, description, lines} ->
          %{
            "name" => name,
            "description" => description,
            "gate" =>
              Cratis.Arc.Availability.Declaration.gate(lines) || %{"kind" => "all", "items" => []}
          }
        end),
      scopes:
        Enum.map(scopes, fn {namespace, lines} ->
          %{
            "namespace" => namespace,
            "gate" =>
              Cratis.Arc.Availability.Declaration.gate(lines) || %{"kind" => "all", "items" => []}
          }
        end),
      values:
        Enum.map(values, fn {name, provider, opts} ->
          %{name: name, provider: provider, required: Keyword.get(opts, :required, false)}
        end)
    }
  end

  @doc false
  def empty, do: %{audiences: [], blocks: [], scopes: [], values: []}
end
