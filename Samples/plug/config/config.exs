# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

import Config

config :counters, Counters.Arc, introspection: :anonymous

import_config "#{config_env()}.exs"
