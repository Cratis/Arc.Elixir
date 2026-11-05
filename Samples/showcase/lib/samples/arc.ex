# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.Arc do
  @moduledoc """
  The Arc application of the showcase: it discovers every command and read model under `Samples`.

  Configuration is in `config/runtime.exs`.
  """

  use Arc.Application, otp_app: :showcase
end
