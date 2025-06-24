email =
  Swoosh.Email.new()
  |> Swoosh.Email.from("max@elektrine.com")
  |> Swoosh.Email.to("arblarg01@gmail.com")
  |> Swoosh.Email.subject("Test SMTP")
  |> Swoosh.Email.text_body("This is a test email via SMTP")

case Elektrine.Mailer.deliver(email) do
  {:ok, result} -> IO.puts("✅ Email sent successfully: #{inspect(result)}")
  {:error, reason} -> IO.puts("❌ Email failed: #{inspect(reason)}")
end
