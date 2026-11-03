# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Library.Web.ErrorHTML do
  @moduledoc false

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
