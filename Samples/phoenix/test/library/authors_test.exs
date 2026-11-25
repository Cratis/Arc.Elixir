# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.AuthorsTest do
  use Cratis.Arc.Test.Case,
    application: Library.Arc,
    event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]

  alias Library.Authors.{AuthorRegistered, AuthorRenamed}
  alias Library.Authors.Registration.{RegisterAuthor, RenameAuthor}

  test "registering an author records AuthorRegistered on the author's event source", %{arc: arc} do
    id = Cratis.Arc.new_id()

    result =
      Cratis.Arc.Test.execute(arc, {RegisterAuthor, %{"id" => id, "name" => "Ada Lovelace"}})

    Cratis.Arc.Test.assert_success(result)

    Cratis.Arc.Test.assert_appended(arc, %AuthorRegistered{name: "Ada Lovelace"},
      event_source_id: id
    )
  end

  test "a name that is too short is rejected before anything is recorded", %{arc: arc} do
    result =
      Cratis.Arc.Test.execute(
        arc,
        {RegisterAuthor, %{"id" => Cratis.Arc.new_id(), "name" => "A"}}
      )

    Cratis.Arc.Test.assert_invalid(result, :name)
    Cratis.Arc.Test.refute_appended(arc, AuthorRegistered)
  end

  test "a reserved name is rejected by the command's own rule", %{arc: arc} do
    result =
      Cratis.Arc.Test.execute(
        arc,
        {RegisterAuthor, %{"id" => Cratis.Arc.new_id(), "name" => "admin"}}
      )

    assert [%{message: "That name is reserved.", members: [:name]}] = result.validation_results
  end

  test "two authors cannot share a name: Chronicle's constraint becomes a validation result", %{
    arc: arc
  } do
    first =
      Cratis.Arc.Test.execute(
        arc,
        {RegisterAuthor, %{"id" => Cratis.Arc.new_id(), "name" => "Grace Hopper"}}
      )

    second =
      Cratis.Arc.Test.execute(
        arc,
        {RegisterAuthor, %{"id" => Cratis.Arc.new_id(), "name" => "Grace Hopper"}}
      )

    Cratis.Arc.Test.assert_success(first)

    assert [
             %{
               reason: "constraintViolation",
               message: "An author with that name is already registered."
             }
           ] =
             second.validation_results
  end

  test "only editors may rename", %{arc: arc} do
    id = Cratis.Arc.new_id()
    command = {RenameAuthor, %{"id" => id, "name" => "Ada King"}}

    Cratis.Arc.Test.assert_forbidden(Cratis.Arc.Test.execute(arc, command))

    Cratis.Arc.Test.assert_forbidden(
      Cratis.Arc.Test.execute(arc, command, principal: Cratis.Arc.Test.principal("ada"))
    )

    result =
      Cratis.Arc.Test.execute(arc, command,
        principal: Cratis.Arc.Test.principal("ed", ["editor"])
      )

    Cratis.Arc.Test.assert_success(result)
    Cratis.Arc.Test.assert_appended(arc, %AuthorRenamed{name: "Ada King"}, event_source_id: id)
  end
end
