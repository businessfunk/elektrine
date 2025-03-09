defmodule Elektrine.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias Elektrine.Accounts.UserToken

  @moduledoc """
  Schema for user tokens used in password reset and other authentication flows.
  
  ## Fields
  
  * `:token` - The unique token string
  * `:context` - The context of the token (e.g., "password_reset")
  * `:sent_to` - The email address the token was sent to
  * `:user_id` - The ID of the user the token belongs to
  """

  @rand_size 32
  
  # Token valid for 24 hours (86400 seconds)
  @reset_password_validity_in_seconds 86_400

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Elektrine.Accounts.User

    timestamps(updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Generates a token for password reset.
  """
  def build_password_reset_token(user, email) do
    token = :crypto.strong_rand_bytes(@rand_size)
    
    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: token,
       context: "password_reset",
       sent_to: email,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.
  
  The query returns the user found by the token.
  """
  def verify_password_reset_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = decoded_token

        query =
          from token in token_and_context_query(hashed_token, "password_reset"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(@reset_password_validity_in_seconds, "second"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the given token with the given context.
  """
  def token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end 