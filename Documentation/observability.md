---
title: Observability
description: Telemetry events, Logger metadata and correlation identifiers that let you trace one command or query from the request to the event in Chronicle.
---

When a command misbehaves you need to follow one request through the logs, the metrics and the event store. Arc gives every run a correlation id and emits telemetry around it.

## Correlation

Every request has a correlation id. A valid UUID in `X-Correlation-ID` is reused; anything else is replaced with a fresh one. The effective id is echoed in the response header, appears as `correlationId` in the result envelope, is passed to Chronicle on every append, and is set as `Logger` metadata while the artifact runs. Searching for it finds the request, the log lines and the events it recorded.

Correlation is diagnostic identity. It carries no authority.

## Logger metadata

While a command or query runs, these keys are set on the process:

| Key | Value |
| --- | --- |
| `:arc_correlation_id` | The correlation id |
| `:arc_tenant` | The tenant header value, or `nil` |

Add them to your formatter to see them:

```elixir
config :logger, :default_formatter, metadata: [:arc_correlation_id, :arc_tenant]
```

## Telemetry

Arc wraps each run in a `:telemetry.span/3`.

| Event | Metadata |
| --- | --- |
| `[:arc, :command, :start]`, `[:arc, :command, :stop]` | `command` (module), `correlation_id`; `stop` adds `success?` |
| `[:arc, :query, :start]`, `[:arc, :query, :stop]` | `read_model` (module), `query` (name), `correlation_id`; `stop` adds `success?` |

`stop` carries the usual `duration` measurement. A failed run is still a `stop` with `success?: false`; the failure is in the result, not an exception. A handler that raises is caught, logged with the stack trace and the correlation id, and returned as an exception result.

```elixir
:telemetry.attach(
  "arc-commands",
  [:arc, :command, :stop],
  fn _event, %{duration: duration}, %{command: command, success?: success?}, _config ->
    Logger.info("#{inspect(command)} took #{System.convert_time_unit(duration, :native, :millisecond)} ms, success: #{success?}")
  end,
  nil
)
```

Chronicle emits its own telemetry and OpenTelemetry spans for the appends Arc makes; see the Chronicle client's observability documentation.

## Exceptions

Exception detail is logged server-side first, then replaced in the result by a generic message unless `expose_exceptions` is `true`. The correlation id is kept either way, so a user report with that id is enough to find the stack trace.
