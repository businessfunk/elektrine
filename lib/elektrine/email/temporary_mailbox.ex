defmodule Elektrine.Email.TemporaryMailbox do
  use Ecto.Schema
  import Ecto.Changeset

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
  """
  def generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64()
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 32)
  end
  
  @doc """
  Generates a random email address for a temporary mailbox.
  """
  def generate_email do
    username = generate_random_username()
    domain = Application.get_env(:elektrine, :email)[:domain] || "elektrine.com"
    "#{username}@#{domain}"
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