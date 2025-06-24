defmodule Elektrine.Email.TemporaryMailbox do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "temporary_mailboxes" do
    field :email, :string
    field :token, :string
    field :expires_at, :utc_datetime

    has_many :messages, Elektrine.Email.Message, foreign_key: :mailbox_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new temporary mailbox.
  """
  def changeset(mailbox, attrs) do
    mailbox
    |> cast(attrs, [:email, :token, :expires_at])
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
    token = :crypto.strong_rand_bytes(32)
    |> Base.url_encode64()
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 32)
    
    # Check if this token has ever been used
    token_exists = Elektrine.Repo.exists?(
      from(t in __MODULE__, where: t.token == ^token)
    )
    
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
    temp_exists = Elektrine.Repo.exists?(
      from(t in __MODULE__, where: t.email == ^email)
    )
    
    mailbox_exists = Elektrine.Repo.exists?(
      from(m in Elektrine.Email.Mailbox, where: m.email == ^email)
    )
    
    if temp_exists or mailbox_exists do
      # Email already used, try again
      generate_unique_email(domain, attempts + 1)
    else
      email
    end
  end
  
  @doc """
  Generates a random username for a temporary email.
  """
  def generate_random_username do
    random_part = :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
    
    "temp-#{random_part}"
  end
end