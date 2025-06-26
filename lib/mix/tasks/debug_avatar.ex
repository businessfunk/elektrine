defmodule Mix.Tasks.Debug.Avatar do
  @moduledoc """
  Debug avatar upload functionality
  """
  
  use Mix.Task

  def run(_) do
    Mix.Task.run("app.start")
    
    IO.puts("=== Avatar Upload Debug ===")
    
    # Check ImageMagick availability
    IO.puts("\n1. Checking ImageMagick availability:")
    case System.cmd("identify", ["-version"], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("✅ ImageMagick is available")
        IO.puts("Version: #{String.split(output, "\n") |> hd()}")
      {error, _} ->
        IO.puts("❌ ImageMagick not found or not working")
        IO.puts("Error: #{error}")
    end
    
    # Check upload configuration
    IO.puts("\n2. Upload configuration:")
    config = Application.get_env(:elektrine, :uploads, [])
    IO.inspect(config, label: "Upload config")
    
    # Check ExAws configuration
    IO.puts("\n3. ExAws/S3 configuration:")
    ex_aws_config = Application.get_env(:ex_aws, :s3, [])
    IO.inspect(ex_aws_config, label: "ExAws S3 config")
    
    # Test S3 connection if configured
    if Keyword.get(config, :adapter) == :s3 do
      IO.puts("\n4. Testing S3 connection:")
      bucket = Keyword.get(config, :bucket)
      
      if bucket do
        case ExAws.S3.list_objects(bucket, max_keys: 1) |> ExAws.request() do
          {:ok, _} ->
            IO.puts("✅ S3 connection successful")
          {:error, error} ->
            IO.puts("❌ S3 connection failed")
            IO.inspect(error, label: "S3 error")
        end
      else
        IO.puts("❌ No bucket configured")
      end
    end
    
    # Check environment variables
    IO.puts("\n5. Environment variables:")
    env_vars = [
      "BACKBLAZE_KEY_ID",
      "BACKBLAZE_APPLICATION_KEY", 
      "BACKBLAZE_BUCKET_NAME",
      "BACKBLAZE_ENDPOINT"
    ]
    
    for var <- env_vars do
      value = System.get_env(var)
      status = if value && String.length(value) > 0, do: "✅ Set", else: "❌ Missing"
      IO.puts("#{var}: #{status}")
    end
  end
end