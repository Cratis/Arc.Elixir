# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

url = System.get_env("MONGODB_URL", "mongodb://localhost:27017/?replicaSet=rs0")

unless Arc.MongoDB.Test.available?(url) do
  IO.puts("No MongoDB answers at #{url}: the :mongodb tests are skipped.")
  ExUnit.configure(exclude: [:mongodb])
end

ExUnit.start()
