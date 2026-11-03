# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

# Generates TypeScript proxies for the test fixtures into ContractTests/TypeScript/generated.
# Run from Source/arc with MIX_ENV=test.

output = Path.expand("../../ContractTests/TypeScript/generated", File.cwd!())
File.rm_rf!(output)

case Arc.ProxyGenerator.generate(ArcFixtures.App, output: output) do
  {:ok, result} -> IO.puts("Generated #{length(result.written)} files into #{output}")
  {:error, messages} -> Mix.raise(Enum.join(messages, "\n"))
end
