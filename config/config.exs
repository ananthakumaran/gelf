use Mix.Config

config :logger,
  handle_sasl_reports: true

config :logger, :console,
  level: :warn

config :logger, Gelf,
  chunk_size: 100
