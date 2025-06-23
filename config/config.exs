# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elektrine,
  ecto_repos: [Elektrine.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure email settings
config :elektrine, :email,
  domain: System.get_env("EMAIL_DOMAIN") || "elektrine.com",
  # Supported domains for multi-domain access
  supported_domains: [
    "elektrine.com",
    "z.org"
  ]

# Configures the endpoint
config :elektrine, ElektrineWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ElektrineWeb.ErrorHTML, json: ElektrineWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Elektrine.PubSub,
  live_view: [signing_salt: "ewG/v8k5"]

# Configures the mailer
#
# Use SMTP adapter as a placeholder - we'll override in runtime
config :elektrine, Elektrine.Mailer,
  adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  elektrine: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  elektrine: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Swoosh API client
config :swoosh, :api_client, Swoosh.ApiClient.Hackney

# Quantum scheduler configuration
config :elektrine, Elektrine.Scheduler,
  jobs: [
    # Run cleanup of expired temporary mailboxes every hour
    {"0 * * * *", {Elektrine.Email.Cleanup, :perform_scheduled_cleanup, []}}
  ]

# Backblaze B2 configuration for file uploads
config :ex_aws,
  access_key_id: System.get_env("BACKBLAZE_KEY_ID"),
  secret_access_key: System.get_env("BACKBLAZE_APPLICATION_KEY"),
  region: "auto",
  json_codec: Jason,
  s3: [
    scheme: "https://",
    host: System.get_env("BACKBLAZE_ENDPOINT") || "s3.us-west-002.backblazeb2.com",
    region: "auto"
  ]

config :elektrine, :uploads,
  adapter: :s3,
  bucket: System.get_env("BACKBLAZE_BUCKET_NAME") || "elektrine-uploads-prod",
  endpoint: System.get_env("BACKBLAZE_ENDPOINT") || "s3.us-west-002.backblazeb2.com",
  # Upload security limits
  max_file_size: 5 * 1024 * 1024,  # 5MB
  max_image_width: 2048,
  max_image_height: 2048

# hCaptcha configuration
config :elektrine, :hcaptcha,
  site_key: System.get_env("HCAPTCHA_SITE_KEY"),
  secret_key: System.get_env("HCAPTCHA_SECRET_KEY"),
  verify_url: "https://hcaptcha.com/siteverify"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
