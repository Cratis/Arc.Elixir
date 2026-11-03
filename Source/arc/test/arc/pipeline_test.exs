# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.PipelineTest do
  use Arc.Test.Case,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered],
    reducers: [ArcFixtures.Authors.AuthorReducer]

  import ExUnit.CaptureLog

  alias ArcFixtures.Authors.AuthorId
  alias ArcFixtures.Authors.AuthorRegistered
  alias ArcFixtures.Authors.Registration.{Explode, RegisterAuthor, RenameAuthor}

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"

  describe "executing a command" do
    test "appends the returned event to the key's event source", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RegisterAuthor{id: struct(AuthorId, value: @id), name: "Ada"})

      Arc.Test.assert_success(result)
      Arc.Test.assert_appended(arc, AuthorRegistered, event_source_id: @id)
      assert [%AuthorRegistered{name: "Ada"}] = result.events
    end

    test "binds a wire map with camelCase keys", %{arc: arc} do
      result =
        Arc.Test.execute(
          arc,
          {RegisterAuthor, %{"id" => @id, "name" => "Ada", "age" => 36, "tags" => ["a"]}}
        )

      Arc.Test.assert_success(result)
    end

    test "rejects a value of the wrong type as a malformed request", %{arc: arc} do
      result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => "not-a-uuid", "name" => "Ada"}})

      Arc.Test.assert_invalid(result, :id)
      assert [%{reason: "malformedRequest"}] = result.validation_results
      Arc.Test.refute_appended(arc, AuthorRegistered)
    end

    test "evaluates declarative rules and does not append", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RegisterAuthor{
          id: struct(AuthorId, value: @id),
          name: "much too long a name",
          email: "nope",
          age: 200
        })

      Arc.Test.assert_invalid(result, :name)
      Arc.Test.assert_invalid(result, :email)
      Arc.Test.assert_invalid(result, :age)
      Arc.Test.refute_appended(arc, AuthorRegistered)
    end

    test "requires required fields", %{arc: arc} do
      result = Arc.Test.execute(arc, %RegisterAuthor{id: struct(AuthorId, value: @id), name: ""})

      Arc.Test.assert_invalid(result, :name)
    end

    test "runs the command's own validate callback", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RegisterAuthor{id: struct(AuthorId, value: @id), name: "forbidden"})

      assert [%{message: "That name is not allowed.", members: [:name]}] =
               result.validation_results
    end

    test "drops results at or below the allowed severity", %{arc: arc} do
      warn = Arc.Validation.warning("careful", [:name])
      assert Arc.ValidationResult.severity_value(warn.severity) == 2

      result =
        Arc.Test.execute(
          arc,
          %RegisterAuthor{id: struct(AuthorId, value: @id), name: "forbidden"},
          allowed_severity: 3
        )

      Arc.Test.assert_success(result)
    end

    test "validate_only does not append", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RegisterAuthor{id: struct(AuthorId, value: @id), name: "Ada"},
          validate_only: true
        )

      Arc.Test.assert_success(result)
      Arc.Test.refute_appended(arc, AuthorRegistered)
    end
  end

  describe "identity in Chronicle" do
    test "the caller is the identity the append is made with" do
      ctx = %Arc.Context{principal: Arc.Test.principal("ada"), correlation_id: "c1"}

      opts = Arc.Chronicle.options(ctx)

      assert opts[:correlation_id] == "c1"
      assert %Chronicle.Identity{subject: "ada", name: "ada", on_behalf_of: nil} = opts[:identity]
    end

    test "an actor acting for a user is the identity, on behalf of that user" do
      principal = %{
        Arc.Test.principal("ada")
        | actor: Arc.Principal.new("support", "Support Person")
      }

      ctx = %Arc.Context{principal: principal, correlation_id: "c1"}

      assert %Chronicle.Identity{
               subject: "support",
               name: "Support Person",
               on_behalf_of: %Chronicle.Identity{subject: "ada"}
             } = Arc.Chronicle.options(ctx)[:identity]
    end
  end

  describe "authorization" do
    test "denies an anonymous caller when roles are required", %{arc: arc} do
      result = Arc.Test.execute(arc, %RenameAuthor{id: @id, name: "Ada"})

      Arc.Test.assert_forbidden(result)
      assert result.authorization_failure_reason =~ "Authentication"
      assert Arc.CommandResult.status(result) == 403
    end

    test "denies an authenticated caller without the role", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RenameAuthor{id: @id, name: "Ada"},
          principal: Arc.Test.principal("bob")
        )

      Arc.Test.assert_forbidden(result)
      assert result.authorization_failure_reason =~ "admin"
    end

    test "admits a caller in the role, provides values, and returns the response", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %RenameAuthor{id: @id, name: "Ada"},
          principal: Arc.Test.principal("root", ["admin"])
        )

      Arc.Test.assert_success(result)
      assert result.response == "previous-" <> @id
      assert %{"response" => "previous-" <> _} = Arc.CommandResult.to_wire(result)
    end
  end

  describe "failures" do
    test "an exception becomes a redacted exception result", %{arc: arc} do
      {result, log} = with_log(fn -> Arc.Test.execute(arc, %Explode{id: @id}) end)

      assert log =~ "boom"

      assert Arc.CommandResult.status(result) == 500
      assert [message] = result.exception_messages
      refute message =~ "boom"
      assert result.exception_stack_trace == ""
    end

    test "the result carries the correlation id", %{arc: arc} do
      result =
        Arc.Test.execute(arc, %Explode{id: @id},
          correlation_id: "11111111-1111-4111-8111-111111111111"
        )

      assert Arc.CommandResult.to_wire(result)["correlationId"] ==
               "11111111-1111-4111-8111-111111111111"
    end
  end

  describe "the wire envelope" do
    test "a successful result", %{arc: arc} do
      wire =
        arc
        |> Arc.Test.execute(%RegisterAuthor{id: struct(AuthorId, value: @id), name: "Ada"})
        |> Arc.CommandResult.to_wire()

      assert %{
               "isAuthorized" => true,
               "isValid" => true,
               "isSuccess" => true,
               "hasExceptions" => false,
               "validationResults" => [],
               "exceptionMessages" => []
             } = wire

      refute Map.has_key?(wire, "response")
    end

    test "a validation failure", %{arc: arc} do
      wire =
        arc
        |> Arc.Test.execute({RegisterAuthor, %{"id" => @id, "name" => ""}})
        |> Arc.CommandResult.to_wire()

      assert %{"isValid" => false, "isSuccess" => false} = wire

      assert [%{"severity" => 3, "members" => ["name"], "reason" => "rule"}] =
               wire["validationResults"]
    end
  end
end
