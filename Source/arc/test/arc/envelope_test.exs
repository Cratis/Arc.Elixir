# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.EnvelopeTest do
  # The result envelopes are the contract with the frontend packages. These specs pin the exact
  # field sets and types of the Arc HTTP contract so a change here is deliberate.
  use Arc.Test.Case,
    application: ArcFixtures.App,
    event_types: [ArcFixtures.Authors.AuthorRegistered]

  import ExUnit.CaptureLog

  alias ArcFixtures.Authors.Listing.Authors
  alias ArcFixtures.Authors.Registration.{Explode, RegisterAuthor, RenameAuthor}

  @id "7f4d0f4e-0f4e-4d0f-8f4e-0f4e4d0f8f4e"
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @command_keys ~w(authorizationFailureReason correlationId exceptionMessages exceptionStackTrace hasExceptions isAuthorized isSuccess isValid validationResults)
  @query_keys ~w(correlationId exceptionMessages exceptionStackTrace hasExceptions isAuthorized isReady isSuccess isValid paging validationResults)

  defp keys(wire), do: wire |> Map.keys() |> Enum.sort()

  defp command(arc, command, opts \\ []),
    do: arc |> Arc.Test.execute(command, opts) |> Arc.CommandResult.to_wire()

  defp query(arc, name, args \\ %{}, opts \\ []),
    do: arc |> Arc.Test.query(Authors, name, args, opts) |> Arc.QueryResult.to_wire()

  setup do
    ArcFixtures.Store.put([%ArcFixtures.Authors.Author{id: @id, name: "Ada"}])
    :ok
  end

  describe "the command result envelope" do
    test "a success carries exactly the contract fields and no response when there is none", %{
      arc: arc
    } do
      wire = command(arc, {RegisterAuthor, %{"id" => @id, "name" => "Ada"}})

      assert keys(wire) == Enum.sort(@command_keys)
      assert wire["correlationId"] =~ @uuid

      assert %{
               "isAuthorized" => true,
               "isValid" => true,
               "isSuccess" => true,
               "hasExceptions" => false
             } = wire

      assert %{
               "validationResults" => [],
               "exceptionMessages" => [],
               "exceptionStackTrace" => "",
               "authorizationFailureReason" => ""
             } = wire
    end

    test "a response is carried only on success", %{arc: arc} do
      wire =
        command(arc, {RenameAuthor, %{"id" => @id, "name" => "Ada"}},
          principal: Arc.Test.principal("root", ["admin"])
        )

      assert keys(wire) == Enum.sort(["response" | @command_keys])
      assert wire["response"] == "previous-" <> @id
    end

    test "a validation failure is not valid, has no response and describes each result", %{
      arc: arc
    } do
      wire = command(arc, {RegisterAuthor, %{"id" => @id, "name" => ""}})

      assert keys(wire) == Enum.sort(@command_keys)

      assert %{
               "isAuthorized" => true,
               "isValid" => false,
               "isSuccess" => false,
               "hasExceptions" => false
             } = wire

      assert [result] = wire["validationResults"]
      assert keys(result) == ~w(members message reason severity)
      assert %{"severity" => 3, "members" => ["name"], "reason" => "rule"} = result
      assert is_binary(result["message"])
    end

    test "a result may carry state and a reason detail", %{arc: _arc} do
      wire =
        Arc.ValidationResult.to_wire(
          Arc.Validation.error("x", [:name],
            state: %{n: 1},
            reason: "constraintViolation",
            reason_detail: "unique-name"
          )
        )

      assert keys(wire) == ~w(members message reason reasonDetail severity state)
      assert %{"reason" => "constraintViolation", "reasonDetail" => "unique-name"} = wire
    end

    test "an authorization failure is not authorized and says why", %{arc: arc} do
      wire = command(arc, {RenameAuthor, %{"id" => @id, "name" => "Ada"}})

      assert keys(wire) == Enum.sort(@command_keys)
      assert %{"isAuthorized" => false, "isSuccess" => false, "isValid" => true} = wire
      assert wire["authorizationFailureReason"] != ""
    end

    test "an exception sets hasExceptions and redacts the detail", %{arc: arc} do
      {wire, _log} = with_log(fn -> command(arc, %Explode{id: @id}) end)

      assert keys(wire) == Enum.sort(@command_keys)

      assert %{
               "hasExceptions" => true,
               "isSuccess" => false,
               "isValid" => true,
               "exceptionStackTrace" => ""
             } = wire

      assert [message] = wire["exceptionMessages"]
      refute message =~ "boom"
    end

    test "the status follows the contract order: authorization, validation, then exception", %{
      arc: arc
    } do
      assert Arc.CommandResult.status(
               Arc.Test.execute(arc, {RegisterAuthor, %{"id" => @id, "name" => "Ada"}})
             ) == 200

      assert Arc.CommandResult.status(
               Arc.Test.execute(arc, {RegisterAuthor, %{"id" => @id, "name" => ""}})
             ) == 400

      assert Arc.CommandResult.status(
               Arc.Test.execute(arc, {RenameAuthor, %{"id" => @id, "name" => "A"}})
             ) == 403
    end
  end

  describe "the query result envelope" do
    test "a success carries exactly the contract fields, data and the paging block", %{arc: arc} do
      wire = query(arc, :all_authors)

      assert keys(wire) == Enum.sort(["data" | @query_keys])
      assert wire["correlationId"] =~ @uuid

      assert %{
               "isReady" => true,
               "isAuthorized" => true,
               "isValid" => true,
               "isSuccess" => true,
               "hasExceptions" => false
             } = wire

      assert keys(wire["paging"]) == ~w(page size totalItems totalPages)
      assert %{"page" => 0, "size" => 0, "totalItems" => 1, "totalPages" => 0} = wire["paging"]
    end

    test "totalPages is the ceiling of totalItems over size", %{arc: arc} do
      ArcFixtures.Store.put(
        for n <- 1..5, do: %ArcFixtures.Authors.Author{id: "#{n}", name: "A#{n}"}
      )

      wire = query(arc, :all_authors, %{}, page: 1, page_size: 2)

      assert %{"page" => 1, "size" => 2, "totalItems" => 5, "totalPages" => 3} = wire["paging"]
      assert length(wire["data"]) == 2
    end

    test "data is omitted when the query returns nothing", %{arc: arc} do
      wire = query(arc, :by_id, %{id: "11111111-1111-4111-8111-111111111111"})

      assert keys(wire) == Enum.sort(@query_keys)
      assert wire["isSuccess"] == true
    end

    test "a failure never carries data", %{arc: arc} do
      wire = query(arc, :by_id)

      assert keys(wire) == Enum.sort(@query_keys)
      assert %{"isValid" => false, "isSuccess" => false} = wire
      assert [%{"reason" => "malformedRequest"}] = wire["validationResults"]
    end

    test "an unauthorized query is not authorized and carries no data", %{arc: arc} do
      wire = query(arc, :secret_authors)

      assert keys(wire) == Enum.sort(@query_keys)
      assert %{"isAuthorized" => false, "isSuccess" => false} = wire
    end

    test "the delta change set is never present", %{arc: arc} do
      refute Map.has_key?(query(arc, :all_authors), "changeSet")
    end
  end
end
