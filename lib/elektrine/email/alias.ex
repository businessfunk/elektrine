defmodule Elektrine.Email.Alias do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

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
    |> validate_alias_limit()
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
          # Also check if this email would conflict with existing usernames
          validate_alias_not_username(changeset, alias_email)
        
        _mailbox ->
          add_error(changeset, :alias_email, "this email address is already in use as a mailbox")
      end
    else
      changeset
    end
  end

  defp validate_alias_not_username(changeset, alias_email) do
    # Extract local part from email (before @)
    case String.split(alias_email, "@") do
      [local_part, domain] ->
        allowed_domains = ["elektrine.com", "z.org"]
        
        # Only check for username conflicts on our domains
        if String.downcase(domain) in allowed_domains do
          # Check if local part matches any existing username
          case Elektrine.Repo.get_by(Elektrine.Accounts.User, username: local_part) do
            nil ->
              changeset
            
            _user ->
              add_error(changeset, :alias_email, "this alias conflicts with an existing username")
          end
        else
          changeset
        end
      
      _ ->
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

  defp validate_alias_limit(changeset) do
    user_id = get_field(changeset, :user_id)
    
    if user_id do
      # Check if this is a new alias (no ID) or an existing one being updated
      alias_id = get_field(changeset, :id)
      
      # Count existing aliases for this user, excluding the current one if updating
      existing_count = 
        if alias_id do
          Elektrine.Repo.aggregate(
            from(a in Elektrine.Email.Alias, where: a.user_id == ^user_id and a.id != ^alias_id),
            :count
          )
        else
          Elektrine.Repo.aggregate(
            from(a in Elektrine.Email.Alias, where: a.user_id == ^user_id),
            :count
          )
        end
      
      if existing_count >= 100 do
        add_error(changeset, :alias_email, "you can only have up to 100 aliases per account")
      else
        changeset
      end
    else
      changeset
    end
  end
end