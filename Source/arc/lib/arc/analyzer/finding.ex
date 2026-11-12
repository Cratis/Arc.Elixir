# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.Analyzer.Finding do
  @moduledoc """
  What a rule reports: where the problem is and what it is.

  A rule does not pick its own severity or write the documentation link. The runner
  (`Arc.Analyzer.Runner`) stamps the rule id, the configured severity and the link onto the
  diagnostic, so users can retune a rule without the rule knowing.

    * `:module` - the module the finding belongs to. Suppression
      (`@arc_analyzer ignore: [...]`) is looked up on this module.
    * `:file` - the absolute path of the source file.
    * `:line` - the 1-based line.
    * `:message` - a short, actionable sentence without the rule id.
  """

  @enforce_keys [:module, :file, :line, :message]
  defstruct [:module, :file, :line, :message]

  @type t :: %__MODULE__{
          module: module(),
          file: String.t(),
          line: pos_integer(),
          message: String.t()
        }
end
