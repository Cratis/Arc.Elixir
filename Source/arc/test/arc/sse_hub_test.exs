# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.SseHubTest do
  # Not async: the Arc application supervisor is registered by name.
  use Arc.Test.Case,
    application: ArcFixtures.App,
    configure: true,
    event_types: [ArcFixtures.Authors.AuthorRegistered],
    observable: true

  defmodule Host do
    use Plug.Builder
    plug(Arc.Plug, application: ArcFixtures.App)
    plug(:not_found)
    def not_found(conn, _), do: conn |> send_resp(404, "") |> halt()
  end

  @query "ArcFixtures.Authors.Listing.Authors.LiveAuthors"

  setup do
    ArcFixtures.Store.put([
      %ArcFixtures.Authors.Author{id: "a", name: "Ada"},
      %ArcFixtures.Authors.Author{id: "b", name: "Bob"}
    ])

    previous = Application.get_env(:cratis_arc, ArcFixtures.App)

    Application.put_env(
      :cratis_arc,
      ArcFixtures.App,
      Keyword.merge(previous || [],
        authentication: [Arc.Authentication.MicrosoftIdentityPlatform],
        trust_forwarded_identity_headers: true
      )
    )

    Arc.Application.refresh(ArcFixtures.App)

    {:ok, server} = Bandit.start_link(plug: Host, port: 0, ip: :loopback)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{port: port}
  end

  # A raw socket: the stream is chunked and Server-Sent Events, and a plain client shows exactly
  # what is on the wire. The unparsed bytes of a socket are kept in the process dictionary.
  defp open(port, headers \\ []) do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

    lines =
      ["GET /.cratis/queries/sse HTTP/1.1", "host: localhost", "accept: text/event-stream"] ++
        for({k, v} <- headers, do: "#{k}: #{v}")

    :ok = :gen_tcp.send(socket, Enum.join(lines, "\r\n") <> "\r\n\r\n")
    Process.put({:buffer, socket}, "")
    on_exit(fn -> :gen_tcp.close(socket) end)
    {socket, next_event(socket)}
  end

  defp to_headers(headers), do: for({k, v} <- headers, do: {to_charlist(k), to_charlist(v)})

  defp next_event(socket, timeout \\ 3_000) do
    case take_event(Process.get({:buffer, socket})) do
      {:ok, event, rest} ->
        Process.put({:buffer, socket}, rest)
        Jason.decode!(event)

      :more ->
        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} ->
            Process.put({:buffer, socket}, Process.get({:buffer, socket}) <> data)
            next_event(socket, timeout)

          {:error, :timeout} ->
            nil
        end
    end
  end

  defp take_event(buffer) do
    case Regex.run(~r/data: (\{.*?\})\n\n/s, buffer, return: :index) do
      [{start, length}, {json_start, json_length}] ->
        json = binary_part(buffer, json_start, json_length)
        rest_start = start + length
        {:ok, json, binary_part(buffer, rest_start, byte_size(buffer) - rest_start)}

      nil ->
        :more
    end
  end

  defp refute_event(socket), do: assert(next_event(socket, 300) == nil)

  defp post(port, action, body, headers \\ []) do
    {:ok, {{_, status, _}, _, _}} =
      :httpc.request(
        :post,
        {~c"http://localhost:#{port}/.cratis/queries/sse/#{action}", to_headers(headers),
         ~c"application/json", Jason.encode!(body)},
        [],
        []
      )

    status
  end

  defp principal(id) do
    json = Jason.encode!(%{identityProvider: "aad", userId: id, userDetails: id, userRoles: []})

    [
      {"x-ms-client-principal", Base.encode64(json)},
      {"x-ms-client-principal-id", id},
      {"x-ms-client-principal-name", id}
    ]
  end

  test "opens with Connected, then streams the subscription's results", %{port: port} do
    {_ref, connected} = open(port)

    assert %{
             "type" => "Connected",
             "payload" => id,
             "keepAliveIntervalMs" => _,
             "supportsSubscriptionRevisions" => true
           } = connected

    assert 200 =
             post(port, "subscribe", %{
               connectionId: id,
               queryId: "q1",
               revision: 1,
               request: %{queryName: @query}
             })
  end

  test "an unknown connection is a 404 and a malformed body a 400", %{port: port} do
    request = %{queryName: @query}

    assert 404 =
             post(port, "subscribe", %{connectionId: "nope", queryId: "q", request: request})

    assert 404 = post(port, "unsubscribe", %{connectionId: "nope", queryId: "q"})
    assert 400 = post(port, "subscribe", %{queryId: "q", request: request})
    assert 400 = post(port, "subscribe", %{connectionId: "x", queryId: "q"})
    assert 400 = post(port, "unsubscribe", %{connectionId: "x"})
  end

  test "only the caller that opened the stream can control it", %{port: port} do
    {ref, %{"payload" => id}} = open(port, principal("alice"))
    request = %{queryName: @query}
    body = %{connectionId: id, queryId: "q1", revision: 1, request: request}

    assert 404 = post(port, "subscribe", body, principal("mallory"))
    assert 404 = post(port, "subscribe", body)
    assert 200 = post(port, "subscribe", body, principal("alice"))

    assert %{"type" => "QueryResult", "queryId" => "q1", "revision" => 1} =
             result = next_event(ref)

    assert length(result["payload"]["data"]) == 2
  end

  test "results are pushed after a notification, and an unsubscribe stops them", %{port: port} do
    {ref, %{"payload" => id}} = open(port)
    request = %{queryName: @query, transferMode: "full"}

    assert 200 = post(port, "subscribe", %{connectionId: id, queryId: "q1", request: request})
    assert %{"type" => "QueryResult"} = next_event(ref)

    ArcFixtures.Store.put(
      ArcFixtures.Store.all() ++ [%ArcFixtures.Authors.Author{id: "c", name: "Cy"}]
    )

    Arc.Notifier.notify(ArcFixtures.App, "authors")

    assert %{"queryId" => "q1", "payload" => %{"data" => data}} = next_event(ref)
    assert length(data) == 3

    assert 200 = post(port, "unsubscribe", %{connectionId: id, queryId: "q1"})
    Process.sleep(50)
    Arc.Notifier.notify(ArcFixtures.App, "authors")
    refute_event(ref)
  end

  test "an unknown query is reported on the stream for that queryId", %{port: port} do
    {ref, %{"payload" => id}} = open(port)

    assert 200 =
             post(port, "subscribe", %{
               connectionId: id,
               queryId: "bad",
               request: %{queryName: "Nope"}
             })

    assert %{"type" => "Error", "queryId" => "bad"} = next_event(ref)
  end

  test "a stale revision is ignored and an unsubscribe tombstone beats a delayed subscribe",
       %{port: port} do
    {ref, %{"payload" => id}} = open(port)
    request = %{queryName: @query, transferMode: "full"}

    assert 200 = post(port, "unsubscribe", %{connectionId: id, queryId: "q", revision: 5})

    assert 200 =
             post(port, "subscribe", %{
               connectionId: id,
               queryId: "q",
               revision: 4,
               request: request
             })

    refute_event(ref)

    assert 400 =
             post(port, "subscribe", %{
               connectionId: id,
               queryId: "q",
               revision: 0,
               request: request
             })
  end

  test "a subscription's tenant comes from its own control request", %{port: port} do
    {ref, %{"payload" => id}} = open(port)

    assert 200 =
             post(
               port,
               "subscribe",
               %{connectionId: id, queryId: "q", request: %{queryName: @query}},
               [{"x-cratis-tenant-id", "acme"}]
             )

    assert %{"type" => "QueryResult"} = next_event(ref)
  end
end
