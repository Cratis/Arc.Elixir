# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.AuthorsTest do
  use Arc.Test.Case,
    application: Library.Arc,
    event_types: [Library.Authors.AuthorRegistered, Library.Authors.AuthorRenamed]

  alias Library.Authors.{AuthorRegistered, AuthorRenamed}
  alias Library.Authors.Registration.{RegisterAuthor, RenameAuthor}

  test "registering an author records AuthorRegistered on the author's event source", %{arc: arc} do
    id = Arc.new_id()

    result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => id, "name" => "Ada Lovelace"}})

    Arc.Test.assert_success(result)
    Arc.Test.assert_appended(arc, %AuthorRegistered{name: "Ada Lovelace"}, event_source_id: id)
  end

  test "a name that is too short is rejected before anything is recorded", %{arc: arc} do
    result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "A"}})

    Arc.Test.assert_invalid(result, :name)
    Arc.Test.refute_appended(arc, AuthorRegistered)
  end

  test "a reserved name is rejected by the command's own rule", %{arc: arc} do
    result = Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "admin"}})

    assert [%{message: "That name is reserved.", members: [:name]}] = result.validation_results
  end

  test "two authors cannot share a name: Chronicle's constraint becomes a validation result", %{
    arc: arc
  } do
    first =
      Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "Grace Hopper"}})

    second =
      Arc.Test.execute(arc, {RegisterAuthor, %{"id" => Arc.new_id(), "name" => "Grace Hopper"}})

    Arc.Test.assert_success(first)

    assert [
             %{
               reason: "constraintViolation",
               message: "An author with that name is already registered."
             }
           ] =
             second.validation_results
  end

  test "only editors may rename", %{arc: arc} do
    id = Arc.new_id()
    command = {RenameAuthor, %{"id" => id, "name" => "Ada King"}}

    Arc.Test.assert_forbidden(Arc.Test.execute(arc, command))

    Arc.Test.assert_forbidden(
      Arc.Test.execute(arc, command, principal: Arc.Test.principal("ada"))
    )

    result = Arc.Test.execute(arc, command, principal: Arc.Test.principal("ed", ["editor"]))

    Arc.Test.assert_success(result)
    Arc.Test.assert_appended(arc, %AuthorRenamed{name: "Ada King"}, event_source_id: id)
  end
end
