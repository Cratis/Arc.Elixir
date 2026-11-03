# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule Arc.LiveView.Form do
    @moduledoc """
    A command as a Phoenix form.

    `Arc.LiveView.Form` implements `Phoenix.HTML.FormData`, so `Phoenix.Component.to_form/2`, `<.form>`
    and the generated `<.input>` core component work with a command directly. Errors from the
    Arc pipeline appear on the matching field, using the member names of the validation results.

    Form values arrive as strings. Empty strings become `nil` for fields that are not strings, and
    keys are `snake_case` field names, which Arc converts to the wire names it binds from.

    You normally use it through `Arc.LiveView.assign_form/4`, `validate_form/3` and `submit_form/3`.
    """

    alias Arc.CommandResult

    defstruct command: nil, params: %{}, errors: [], action: nil

    @type t :: %__MODULE__{
            command: module(),
            params: map(),
            errors: [{atom(), {String.t(), keyword()}}],
            action: atom() | nil
          }

    @doc "A new, empty form for `command`, optionally prefilled with `params`."
    @spec new(module(), map()) :: t()
    def new(command, params \\ %{}), do: %__MODULE__{command: command, params: stringify(params)}

    @doc false
    @spec validate(t(), map(), (map() -> CommandResult.t())) :: t()
    def validate(%__MODULE__{} = form, params, runner) do
      result = runner.(wire(form.command, params))
      %{form | params: params, errors: errors(result), action: :validate}
    end

    @doc false
    @spec submit(t(), map(), (map() -> {:ok, CommandResult.t()} | {:error, CommandResult.t()})) ::
            {:ok, CommandResult.t()} | {:error, t()}
    def submit(%__MODULE__{} = form, params, runner) do
      case runner.(wire(form.command, params)) do
        {:ok, result} ->
          {:ok, result}

        {:error, result} ->
          {:error, %{form | params: params, errors: errors(result), action: :insert}}
      end
    end

    @doc """
    Converts form params to the wire map the pipeline binds: `snake_case` keys become `camelCase`,
    and blank values of non-string fields become `nil`.
    """
    @spec wire(module(), map()) :: map()
    def wire(command, params) do
      types = Map.new(command.__arc_schema__(), &{Atom.to_string(&1.name), &1.type})

      for {key, value} <- params, key = to_string(key), Map.has_key?(types, key), into: %{} do
        {Arc.Naming.camel(key), normalize(Map.fetch!(types, key), value)}
      end
    end

    defp normalize(:string, value), do: value
    defp normalize(type, "") when is_atom(type) or is_tuple(type), do: nil
    defp normalize(_type, value), do: value

    defp errors(%CommandResult{authorized?: false, authorization_failure_reason: reason}),
      do: [{:base, {reason, []}}]

    defp errors(%CommandResult{exception_messages: [message | _]}), do: [{:base, {message, []}}]

    defp errors(%CommandResult{validation_results: results}) do
      Enum.flat_map(results, fn result ->
        case result.members do
          [] -> [{:base, {result.message, []}}]
          members -> Enum.map(members, &{to_atom(&1), {result.message, []}})
        end
      end)
    end

    defp to_atom(member) when is_atom(member), do: member
    defp to_atom(member), do: String.to_existing_atom(member)

    defp stringify(params), do: Map.new(params, fn {k, v} -> {to_string(k), v} end)
  end

  defimpl Phoenix.HTML.FormData, for: Arc.LiveView.Form do
    def to_form(%Arc.LiveView.Form{} = form, options) do
      name = options[:as] || :command
      id = options[:id] || to_string(name)

      %Phoenix.HTML.Form{
        source: form,
        impl: __MODULE__,
        id: id,
        name: to_string(name),
        data: struct(form.command),
        params: form.params,
        errors: if(form.action, do: form.errors, else: []),
        action: form.action,
        options: Keyword.put_new(options, :method, "post")
      }
    end

    def to_form(%Arc.LiveView.Form{}, _form, _field, _options),
      do: raise(ArgumentError, "Arc command forms do not support nested inputs.")

    def input_value(%Arc.LiveView.Form{params: params, command: command}, _form, field) do
      key = to_string(field)

      case params do
        %{^key => value} -> value
        _ -> Map.get(struct(command), field)
      end
    end

    def input_validations(%Arc.LiveView.Form{command: command}, _form, field) do
      case Enum.find(command.__arc_schema__(), &(&1.name == field)) do
        nil -> []
        %{required?: true} -> [required: true]
        _ -> []
      end
    end
  end
end
