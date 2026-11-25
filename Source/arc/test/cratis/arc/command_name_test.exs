# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Cratis.Arc.CommandNameTest do
  use ExUnit.Case, async: true

  defmodule Named.Sample.RenamingThings do
    use Cratis.Arc.Command, id: "rename-thing"

    schema do
      field :id, :string, key: true, required: true
    end

    def handle(_command, _ctx), do: {:ok, nil}
  end

  defmodule Named.Sample.Unnamed do
    use Cratis.Arc.Command

    schema do
      field :id, :string, key: true, required: true
    end

    def handle(_command, _ctx), do: {:ok, nil}
  end

  test "an explicit command id is the last route segment" do
    descriptor = Named.Sample.RenamingThings.__arc__()
    assert descriptor.route_name == "rename-thing"

    assert Cratis.Arc.Descriptor.command_route(descriptor, segments_to_skip: 4) =~
             ~r{/api/sample/rename-thing$}
  end

  test "without an id the module name still decides the route" do
    descriptor = Named.Sample.Unnamed.__arc__()
    assert descriptor.route_name == nil

    assert Cratis.Arc.Descriptor.command_route(descriptor, segments_to_skip: 4) =~
             ~r{/api/sample/unnamed$}
  end

  test "an id that is not kebab-case is rejected at compile time" do
    assert_raise ArgumentError, ~r/kebab-case/, fn ->
      Code.compile_string("""
      defmodule Cratis.Arc.CommandNameTest.Bad do
        use Cratis.Arc.Command, id: "RenameThing"
        schema do
          field :id, :string, key: true
        end
        def handle(_c, _x), do: {:ok, nil}
      end
      """)
    end
  end
end
