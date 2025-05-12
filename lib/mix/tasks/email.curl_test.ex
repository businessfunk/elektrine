defmodule Mix.Tasks.Email.CurlTest do
  use Mix.Task
  require Logger

  @shortdoc "Generate a curl command to test the Postal inbound email endpoint"
  
  def run(_) do
    # Start the application to access config
    Mix.shell().info("Starting the application...")
    Mix.Task.run("app.start")
    
    # Get a user to test with
    user = case Elektrine.Accounts.list_users() do
      [user | _] -> user
      [] -> create_test_user()
    end
    
    # Ensure the user has a mailbox
    mailbox = Elektrine.Email.get_user_mailbox(user.id) || 
              create_test_mailbox(user)
    
    Mix.shell().info("Using mailbox: #{mailbox.email}")
    
    # Generate curl command for testing
    generate_curl_command(mailbox)
  end
  
  defp create_test_user do
    Mix.shell().info("Creating a test user...")
    
    {:ok, user} = Elektrine.Accounts.create_user(%{
      username: "testuser",
      password: "password123",
      password_confirmation: "password123"
    })
    
    user
  end
  
  defp create_test_mailbox(user) do
    Mix.shell().info("Creating a test mailbox...")
    
    {:ok, mailbox} = Elektrine.Email.ensure_user_has_mailbox(user)
    mailbox
  end
  
  defp generate_curl_command(mailbox) do
    # Create a sample raw email
    date = DateTime.utc_now() |> DateTime.to_string()
    message_id = "<test-#{System.system_time(:millisecond)}@example.com>"
    
    raw_email = """
    From: sender@example.com
    To: #{mailbox.email}
    Subject: Test Email #{DateTime.utc_now()}
    Message-ID: #{message_id}
    Date: #{date}
    MIME-Version: 1.0
    Content-Type: multipart/alternative; boundary="boundary-string"

    --boundary-string
    Content-Type: text/plain; charset="UTF-8"
    Content-Transfer-Encoding: quoted-printable

    This is a test email from the curl test.

    --boundary-string
    Content-Type: text/html; charset="UTF-8"
    Content-Transfer-Encoding: quoted-printable

    <html>
    <body>
      <p>This is a <strong>test email</strong> from the curl test.</p>
    </body>
    </html>

    --boundary-string--
    """
    
    # Encode the email in Base64
    base64_message = Base.encode64(raw_email)
    
    # Create JSON payload
    json_payload = Jason.encode!(%{"message" => base64_message})
    
    # Create temporary file for the payload
    payload_file = Path.join(System.tmp_dir(), "postal_test_payload.json")
    File.write!(payload_file, json_payload)
    
    # Generate curl command
    curl_command = """
    
    To test the Postal inbound endpoint, run this curl command:
    
    curl -X POST -H "Content-Type: application/json" -d @#{payload_file} http://localhost:4000/api/postal/inbound
    
    Or if you need to test directly in production:
    
    curl -X POST -H "Content-Type: application/json" -d @#{payload_file} https://your-domain.com/api/postal/inbound
    
    The payload has been saved to: #{payload_file}
    
    """
    
    Mix.shell().info(curl_command)
  end
end