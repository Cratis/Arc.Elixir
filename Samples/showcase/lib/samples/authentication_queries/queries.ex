# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Samples.AuthenticationQueries.Queries do
  @moduledoc """
  Anonymous and authenticated queries side by side, to verify what each caller gets.

  The module requires an authenticated caller; `anonymous` declares otherwise for itself.
  """

  use Arc.ReadModel, model: Samples.AuthenticationQueries.AuthenticationQueryItem
  authorize :authenticated

  alias Samples.AuthenticationQueries.AuthenticationQueryItem

  @doc "The stream for login and pre-auth screens: open to everyone."
  @observe many: false, topics: ["authentication"], allow_anonymous: true
  def anonymous(_args, _ctx), do: {:ok, message("Anonymous stream")}

  @doc "The stream that requires authentication."
  @observe many: false, topics: ["authentication"]
  def authenticated(_args, _ctx), do: {:ok, message("Authenticated stream")}

  defp message(kind) do
    {:ok, time} = Time.from_erl(:calendar.universal_time() |> elem(1))
    %AuthenticationQueryItem{message: "#{kind} — #{Calendar.strftime(time, "%H:%M:%S")}"}
  end
end
