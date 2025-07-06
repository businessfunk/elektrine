defmodule Elektrine.Email.TemporaryMailbox do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "temporary_mailboxes" do
    field :email, :string
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :user, Elektrine.Accounts.User
    has_many :messages, Elektrine.Email.Message, foreign_key: :mailbox_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new temporary mailbox.
  """
  def changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email, :token, :expires_at, :user_id])
    |> validate_required([:email, :token, :expires_at])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> unique_constraint(:token)
  end

  @doc """
  Generates a random token for a temporary mailbox.
  Ensures the token is unique.
  """
  def generate_token do
    generate_unique_token(0)
  end

  defp generate_unique_token(attempts) when attempts < 100 do
    token =
      :crypto.strong_rand_bytes(32)
      |> Base.url_encode64()
      |> String.replace(~r/[^a-zA-Z0-9]/, "")
      |> String.slice(0, 32)

    # Check if this token has ever been used
    token_exists = Elektrine.Repo.exists?(from(t in __MODULE__, where: t.token == ^token))

    if token_exists do
      # Token already used, try again
      generate_unique_token(attempts + 1)
    else
      token
    end
  end

  defp generate_unique_token(_attempts) do
    raise "Failed to generate unique temporary mailbox token after 100 attempts"
  end

  @doc """
  Generates a random email address for a temporary mailbox.
  Optionally accepts a domain override.
  Ensures the email is unique and not reused.
  """
  def generate_email(domain \\ nil) do
    domain = domain || Application.get_env(:elektrine, :email)[:domain] || "elektrine.com"
    generate_unique_email(domain)
  end

  defp generate_unique_email(domain, attempts \\ 0) do
    # Prevent infinite loops
    if attempts > 100 do
      raise "Failed to generate unique temporary email after 100 attempts"
    end

    username = generate_random_username()
    email = "#{username}@#{domain}"

    # Check if this email has ever been used (in both temporary_mailboxes and mailboxes tables)
    temp_exists = Elektrine.Repo.exists?(from(t in __MODULE__, where: t.email == ^email))

    mailbox_exists =
      Elektrine.Repo.exists?(from(m in Elektrine.Email.Mailbox, where: m.email == ^email))

    if temp_exists or mailbox_exists do
      # Email already used, try again
      generate_unique_email(domain, attempts + 1)
    else
      email
    end
  end

  @doc """
  Generates a random username for a temporary email.
  Creates realistic-looking usernames similar to gaming services.
  """
  def generate_random_username do
    # Lists of adjectives and nouns commonly used in gaming usernames
    adjectives = [
      "swift", "brave", "silent", "golden", "silver", "crimson", "azure", "shadow",
      "storm", "thunder", "lightning", "frost", "ember", "cosmic", "mystic", "royal",
      "ancient", "epic", "legendary", "mighty", "fierce", "rapid", "stealth", "cyber",
      "neon", "quantum", "plasma", "ultra", "turbo", "hyper", "mega", "super",
      "dark", "bright", "crystal", "iron", "steel", "blazing", "frozen", "electric"
    ]
    
    nouns = [
      "wolf", "eagle", "tiger", "dragon", "phoenix", "warrior", "knight", "ninja",
      "samurai", "wizard", "mage", "hunter", "ranger", "rogue", "paladin", "sage",
      "champion", "hero", "legend", "master", "chief", "captain", "commander", "ace",
      "ghost", "phantom", "shadow", "storm", "blade", "sword", "shield", "arrow",
      "falcon", "hawk", "raven", "viper", "cobra", "panther", "lion", "bear"
    ]
    
    # Randomly select components
    adjective = Enum.random(adjectives)
    noun = Enum.random(nouns)
    
    # Generate a random number suffix (2-4 digits)
    number = :rand.uniform(9999)
    
    # Randomly choose format
    formats = [
      "#{adjective}#{noun}#{number}",
      "#{String.capitalize(adjective)}#{String.capitalize(noun)}#{number}",
      "#{adjective}_#{noun}_#{number}",
      "#{adjective}#{noun}",
      "#{String.capitalize(noun)}#{number}",
      "#{adjective}#{String.capitalize(noun)}"
    ]
    
    Enum.random(formats)
  end
end
