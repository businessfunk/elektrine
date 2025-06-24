defmodule Elektrine.Contact.Message do
  @moduledoc """
  Contact message schema for contact form submissions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :message, :string
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:name, :email, :message])
    |> validate_required([:name, :email, :message])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:message, min: 10, max: 5000)
    |> validate_format(:email, ~r/@/, message: "must have the @ sign and be valid")
  end
end
