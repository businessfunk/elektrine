defmodule Elektrine.Accounts.TwoFactor do
  @moduledoc """
  Provides functionality for Two-Factor Authentication using TOTP.
  """

  @doc """
  Generates a new TOTP secret for a user.
  """
  def generate_secret do
    NimbleTOTP.secret() |> Base.encode32()
  end

  @doc """
  Generates a TOTP provisioning URI for QR code generation.
  """
  def generate_provisioning_uri(secret, username, issuer \\ "Elektrine") do
    NimbleTOTP.otpauth_uri("#{issuer}:#{username}", secret, issuer: issuer)
  end

  @doc """
  Verifies a TOTP code against the user's secret.
  """
  def verify_totp(secret, code) when is_binary(secret) and is_binary(code) do
    case Integer.parse(code) do
      {numeric_code, ""} when numeric_code >= 0 and numeric_code <= 999_999 ->
        # Pad with leading zeros to ensure 6 digits
        formatted_code = String.pad_leading(code, 6, "0")
        NimbleTOTP.valid?(secret, formatted_code, window: 1)

      _ ->
        false
    end
  end

  def verify_totp(_, _), do: false

  @doc """
  Generates backup codes for account recovery.
  """
  def generate_backup_codes(count \\ 8) do
    1..count
    |> Enum.map(fn _ -> generate_backup_code() end)
  end

  @doc """
  Verifies a backup code against the user's stored backup codes.
  Returns {:ok, remaining_codes} if valid, {:error, :invalid} if not.
  """
  def verify_backup_code(backup_codes, code) when is_list(backup_codes) and is_binary(code) do
    formatted_code = String.upcase(String.trim(code))

    case Enum.find_index(backup_codes, &(&1 == formatted_code)) do
      nil ->
        {:error, :invalid}

      index ->
        remaining_codes = List.delete_at(backup_codes, index)
        {:ok, remaining_codes}
    end
  end

  def verify_backup_code(_, _), do: {:error, :invalid}

  # Private functions

  defp generate_backup_code do
    # Generate 8 character alphanumeric code (excluding similar looking characters)
    chars = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
    
    1..8
    |> Enum.map(fn _ -> Enum.random(String.codepoints(chars)) end)
    |> Enum.join()
  end
end