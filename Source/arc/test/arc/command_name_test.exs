# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.CommandNameTest do
  use ExUnit.Case, async: true

  defmodule Named.Sample.RenamingThings do
    use Arc.Command
    command("rename-thing")

    schema do
      field :id, :string, key: true, required: true
    end

    def handle(_command, _ctx), do: {:ok, nil}
  end

  defmodule Named.Sample.Unnamed do
    use Arc.Command

    schema do
      field :id, :string, key: true, required: true
    end

    def handle(_command, _ctx), do: {:ok, nil}
  end

  test "an explicit command name is the last route segment" do
    descriptor = Named.Sample.RenamingThings.__arc__()
    assert descriptor.route_name == "rename-thing"

    assert Arc.Descriptor.command_route(descriptor, segments_to_skip: 3) =~
             ~r{/api/sample/rename-thing$}
  end

  test "without a declaration the module name still decides the route" do
    descriptor = Named.Sample.Unnamed.__arc__()
    assert descriptor.route_name == nil

    assert Arc.Descriptor.command_route(descriptor, segments_to_skip: 3) =~
             ~r{/api/sample/unnamed$}
  end

  test "a name that is not kebab-case is rejected at compile time" do
    assert_raise ArgumentError, ~r/kebab-case/, fn ->
      Code.compile_string("""
      defmodule Arc.CommandNameTest.Bad do
        use Arc.Command
        command "RenameThing"
        schema do
          field :id, :string, key: true
        end
        def handle(_c, _x), do: {:ok, nil}
      end
      """)
    end
  end
end
