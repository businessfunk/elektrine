defmodule Mix.Tasks.Email.SaveSample do
  use Mix.Task
  require Logger

  @shortdoc "Save a sample Base64 encoded email from logs for testing"
  
  @moduledoc """
  Save a sample Base64 encoded email from the provided input.
  
  This task takes a Base64 encoded message string and saves it to a file for testing.
  
  ## Usage
  
  Copy the base64 message from the logs and pass it as an argument:
  
      mix email.save_sample "WC1Qb3N0YWwtU3BhbT..."
  
  Or pipe it from a file:
  
      cat sample_email.txt | mix email.save_sample
  """
  
  def run([base64_message]) do
    # Use the provided base64 message
    save_message(base64_message)
  end
  
  def run([]) do
    # Read from stdin if no argument was provided
    case IO.read(:stdio, :all) do
      {:error, reason} ->
        Mix.shell().error("Error reading from stdin: #{inspect(reason)}")
      
      input when is_binary(input) and input != "" -> 
        save_message(String.trim(input))
        
      _ ->
        Mix.shell().error("No input provided. Please provide a Base64 encoded message.")
        Mix.shell().info("Usage: mix email.save_sample \"BASE64_STRING\"")
        Mix.shell().info("   or: cat file.txt | mix email.save_sample")
    end
  end
  
  defp save_message(base64_message) do
    # Create a directory for sample emails if it doesn't exist
    samples_dir = Path.join("priv", "email_samples")
    File.mkdir_p!(samples_dir)
    
    # Generate a timestamped filename
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[^\w]/, "_")
    filename = Path.join(samples_dir, "sample_email_#{timestamp}.txt")
    
    # Write the Base64 message to the file
    File.write!(filename, base64_message)
    
    Mix.shell().info("Saved sample email to: #{filename}")
    Mix.shell().info("To debug this email, run: mix email.debug_raw #{filename}")
  end
end