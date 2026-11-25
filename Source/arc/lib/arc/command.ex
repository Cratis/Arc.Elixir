# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Command do
  @moduledoc """
  A model-bound command: a module whose struct is the request and whose `handle/2` decides.

      defmodule MyApp.Authors.Registration.RegisterAuthor do
        @moduledoc "Registers a new author."
        use Arc.Command

        schema do
          field :id, :uuid, key: true, required: true
          field :name, :string, required: true, max_length: 100
        end

        def handle(%__MODULE__{} = command, _ctx) do
          {:append, %MyApp.Authors.AuthorRegistered{name: command.name}}
        end
      end

  ## Callbacks

    * `provide/2` (optional) - load data after authorization and validation; return `:ok`,
      `{:ok, map}` (merged into `ctx.provided`) or `{:error, results}`.
    * `validate/2` (optional) - cross-field rules; return `:ok` or `{:error, results}`.
    * `handle/2` - decide. A command either records what happened or is rejected; it never
      succeeds as a silent no-op.

  ## What `handle/2` returns

    * `{:append, events}` - append one event or a list to Chronicle. The event source id is the
      command's `key: true` field; wrap an event as `{event_source_id, event}` to target another.
    * `{:append, events, response}` - append and return a value to the client.
    * `{:ok, response}` - succeed without recording an event, for example a command that only
      calls a collaborator. Prefer `{:append, ...}` for state changes.
    * `{:error, results}` - reject with a list of (or one) `Arc.ValidationResult`.

  ## Declarations

    * `command/1` - an explicit, stable name for the command's route (optional; see below)
    * `authorize/1` and `allow_anonymous/0` - see `Arc.Authorization`
    * `response/1` - the type returned to the client, for the generated proxy

  ## Naming

  By default the route follows the module path: `MyApp.Authors.Registration.RegisterAuthor` is
  `/api/authors/registration/register-author` (after `segments_to_skip`). Treat the module as the
  equivalent of a namespace and declare the command's own name with `command/1` to decouple the
  route from where the file lives:

      defmodule MyApp.Authors.RegisteringAuthors do
        use Arc.Command
        command "register-author"      # /api/authors/registering-authors/register-author
        ...

  The declaration is optional and non-breaking: without it nothing changes. The name must be
  kebab-case.
  """

  @type result ::
          {:append, term()}
          | {:append, term(), term()}
          | {:ok, term()}
          | {:error, Arc.ValidationResult.t() | [Arc.ValidationResult.t()]}

  @callback handle(struct(), Arc.Context.t()) :: result()
  @callback provide(struct(), Arc.Context.t()) ::
              :ok | {:ok, map()} | {:error, Arc.ValidationResult.t() | [Arc.ValidationResult.t()]}
  @callback validate(struct(), Arc.Context.t()) ::
              :ok | {:error, Arc.ValidationResult.t() | [Arc.ValidationResult.t()]}
  @optional_callbacks provide: 2, validate: 2

  @doc false
  defmacro __using__(_opts) do
    quote do
      use Arc.Schema
      @behaviour Arc.Command
      import Arc.Command,
        only: [command: 1, authorize: 1, allow_anonymous: 0, response: 1, available: 1]

      Module.register_attribute(__MODULE__, :arc_available, accumulate: true)
      @arc_command_name nil
      @arc_authorization nil
      @arc_response nil
      @before_compile Arc.Command
    end
  end

  @doc "Declares the command's own name, used as the last segment of its route. Kebab-case."
  defmacro command(name) when is_binary(name) do
    unless name =~ ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/ do
      raise ArgumentError,
            "command name #{inspect(name)} must be kebab-case, e.g. \"register-author\""
    end

    quote do: @arc_command_name(unquote(name))
  end

  @doc "Declares who may run the command. See `Arc.Authorization`."
  defmacro authorize(requirement) do
    quote do: @arc_authorization(unquote(requirement))
  end

  @doc """
  Declares when the command is available: `available for: "Plus", with: "Reported", when: ...`.
  See `Arc.Availability`. Several declarations all hold.
  """
  defmacro available(lines) do
    quote do: @arc_available(unquote(lines))
  end

  @doc "Allows anonymous callers."
  defmacro allow_anonymous do
    quote do: @arc_authorization(allow_anonymous: true)
  end

  @doc "Declares the response type, for example `response :string` or `response MyApp.Receipt`."
  defmacro response(type) do
    quote do: @arc_response(unquote(type))
  end

  @doc false
  defmacro __before_compile__(env) do
    fields = Arc.Schema.fields_of(env.module)
    {namespace, name} = Arc.Naming.module_parts(env.module)

    authorization =
      Module.get_attribute(env.module, :arc_authorization) |> Arc.Authorization.normalize()

    response = Module.get_attribute(env.module, :arc_response)
    doc = Arc.Docs.summary(Module.get_attribute(env.module, :moduledoc))
    key = Enum.find(fields, & &1.key?)

    descriptor = %Arc.Descriptor{
      kind: :command,
      module: env.module,
      name: name,
      route_name: Module.get_attribute(env.module, :arc_command_name),
      namespace: namespace,
      doc: doc,
      fields: fields,
      response: response,
      key: key && key.name,
      availability:
        env.module
        |> Module.get_attribute(:arc_available)
        |> Enum.reverse()
        |> Arc.Availability.Declaration.gate(),
      authorization: authorization
    }

    quote do
      def __arc__, do: unquote(Macro.escape(descriptor))
    end
  end
end
