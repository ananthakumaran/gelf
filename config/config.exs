use Mix.Config

config :logger,
  handle_sasl_reports: true

config :logger, :console,
  level: :warn
