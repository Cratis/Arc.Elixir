# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Authors.AuthorRenamed do
  @moduledoc "An author was renamed."

  use Chronicle.Events.EventType, id: "library-author-renamed"

  defstruct name: ""
end
