import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :elektrine, Elektrine.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "elektrine_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :elektrine, ElektrineWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "p3JTmnC2C13RxznMWVb90E3nJnoX5xSZWHfpG1ZHQUQ0gDoMN/uDtttPlS6NFvD6",
  server: false

# In test we don't send emails
config :elektrine, Elektrine.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Use local file storage for tests (faster and no external dependencies)
config :elektrine, :uploads,
  adapter: :local,
  uploads_dir: "tmp/test_uploads"
