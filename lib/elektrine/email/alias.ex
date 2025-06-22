defmodule Elektrine.Email.Alias do
  use Ecto.Schema
  import Ecto.Changeset

  alias Elektrine.Accounts.User

  schema "email_aliases" do
    field :alias_email, :string
    field :target_email, :string
    field :enabled, :boolean, default: true
    field :description, :string

    belongs_to :user, User

    timestamps()
  end

  def changeset(alias, attrs) do
    alias
    |> cast(attrs, [:alias_email, :target_email, :enabled, :description, :user_id])
    |> validate_required([:alias_email, :user_id])
    |> validate_format(:alias_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email format")
    |> validate_alias_domain()
    |> validate_alias_not_mailbox()
    |> validate_optional_target_email()
    |> validate_length(:alias_email, max: 255)
    |> validate_length(:target_email, max: 255)
    |> validate_length(:description, max: 500)
    |> unique_constraint(:alias_email, message: "this alias is already taken")
    |> validate_alias_not_target()
  end

  defp validate_alias_domain(changeset) do
    alias_email = get_field(changeset, :alias_email)
    
    if alias_email do
      # Extract domain from email
      case String.split(alias_email, "@") do
        [_local, domain] ->
          allowed_domains = ["elektrine.com", "z.org"]
          
          if String.downcase(domain) in allowed_domains do
            changeset
          else
            add_error(changeset, :alias_email, "must use one of the allowed domains: #{Enum.join(allowed_domains, ", ")}")
          end
        
        _ ->
          # Invalid email format, but this will be caught by the format validation
          changeset
      end
    else
      changeset
    end
  end

  defp validate_alias_not_mailbox(changeset) do
    alias_email = get_field(changeset, :alias_email)
    
    if alias_email do
      # Check if this email is already used as a mailbox
      case Elektrine.Repo.get_by(Elektrine.Email.Mailbox, email: alias_email) do
        nil ->
          changeset
        
        _mailbox ->
          add_error(changeset, :alias_email, "this email address is already in use as a mailbox")
      end
    else
      changeset
    end
  end

  defp validate_optional_target_email(changeset) do
    target_email = get_field(changeset, :target_email)
    
    if target_email && String.trim(target_email) != "" do
      validate_format(changeset, :target_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be a valid email format")
    else
      changeset
    end
  end

  defp validate_alias_not_target(changeset) do
    alias_email = get_field(changeset, :alias_email)
    target_email = get_field(changeset, :target_email)

    if alias_email && target_email && String.trim(target_email) != "" && alias_email == target_email do
      add_error(changeset, :target_email, "cannot be the same as the alias email")
    else
      changeset
    end
  end
end