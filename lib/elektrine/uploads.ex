defmodule Elektrine.Uploads do
  @moduledoc """
  Handles file uploads with support for both local storage and S3.

  Configuration determines which adapter to use:
  - :local for development (stores files locally)
  - :s3 for production (stores files in S3)
  """

  # Default upload limits (can be overridden in config)
  # 5MB
  @default_max_file_size 5 * 1024 * 1024
  @default_max_image_width 2048
  @default_max_image_height 2048
  @allowed_mime_types ~w[
    image/jpeg
    image/jpg
    image/png
    image/gif
    image/webp
  ]
  @allowed_extensions ~w[.jpg .jpeg .png .gif .webp]
  @malicious_patterns [
    # PHP patterns
    ~r/<?php/i,
    ~r/<\?=/i,
    ~r/eval\s*\(/i,
    ~r/exec\s*\(/i,
    ~r/system\s*\(/i,
    ~r/shell_exec\s*\(/i,
    # JavaScript patterns
    ~r/<script/i,
    ~r/javascript:/i,
    ~r/on\w+\s*=/i,
    # HTML injection
    ~r/<iframe/i,
    ~r/<object/i,
    ~r/<embed/i,
    # File inclusion patterns
    ~r/include\s*\(/i,
    ~r/require\s*\(/i,
    # SQL patterns
    ~r/union\s+select/i,
    ~r/drop\s+table/i
  ]

  @doc """
  Uploads a file and returns the public URL.

  Returns {:ok, url} on success or {:error, reason} on failure.
  """
  def upload_avatar(%Plug.Upload{} = upload, user_id) do
    with :ok <- validate_upload(upload) do
      case get_config(:adapter) do
        :local -> upload_local(upload, user_id)
        :s3 -> upload_s3(upload, user_id)
      end
    end
  end

  defp validate_upload(%Plug.Upload{} = upload) do
    with :ok <- validate_file_size(upload),
         :ok <- validate_file_type(upload),
         :ok <- validate_file_extension(upload),
         :ok <- validate_file_content(upload) do
      :ok
    end
  end

  defp validate_file_size(%Plug.Upload{} = upload) do
    max_file_size = get_config(:max_file_size) || @default_max_file_size

    case File.stat(upload.path) do
      {:ok, %File.Stat{size: size}} when size > max_file_size ->
        {:error, {:file_too_large, "File size exceeds #{max_file_size / (1024 * 1024)}MB limit"}}

      {:ok, %File.Stat{size: 0}} ->
        {:error, {:empty_file, "File is empty"}}

      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error, {:file_access_error, reason}}
    end
  end

  defp validate_file_type(%Plug.Upload{content_type: content_type}) do
    if content_type in @allowed_mime_types do
      :ok
    else
      {:error,
       {:invalid_file_type,
        "File type #{content_type} not allowed. Allowed types: #{Enum.join(@allowed_mime_types, ", ")}"}}
    end
  end

  defp validate_file_extension(%Plug.Upload{filename: filename}) do
    extension = filename |> Path.extname() |> String.downcase()

    if extension in @allowed_extensions do
      :ok
    else
      {:error,
       {:invalid_extension,
        "File extension #{extension} not allowed. Allowed extensions: #{Enum.join(@allowed_extensions, ", ")}"}}
    end
  end

  defp validate_file_content(%Plug.Upload{} = upload) do
    with {:ok, content} <- File.read(upload.path),
         :ok <- scan_for_malicious_content(content),
         :ok <- validate_image_dimensions(upload.path) do
      :ok
    end
  end

  defp scan_for_malicious_content(content) do
    # Convert to string for pattern matching
    content_str = if is_binary(content), do: content, else: inspect(content)

    malicious_found =
      Enum.find(@malicious_patterns, fn pattern ->
        Regex.match?(pattern, content_str)
      end)

    case malicious_found do
      nil -> :ok
      _pattern -> {:error, {:malicious_content, "File contains potentially malicious content"}}
    end
  end

  defp validate_image_dimensions(file_path) do
    max_width = get_config(:max_image_width) || @default_max_image_width
    max_height = get_config(:max_image_height) || @default_max_image_height

    case identify_image(file_path) do
      {:ok, {width, height}} ->
        cond do
          width > max_width ->
            {:error, {:image_too_wide, "Image width #{width}px exceeds limit of #{max_width}px"}}

          height > max_height ->
            {:error,
             {:image_too_tall, "Image height #{height}px exceeds limit of #{max_height}px"}}

          true ->
            :ok
        end

      {:error, reason} ->
        {:error, {:invalid_image, "Unable to read image dimensions: #{reason}"}}
    end
  end

  defp identify_image(file_path) do
    case System.cmd("identify", ["-format", "%w %h", file_path], stderr_to_stdout: true) do
      {output, 0} ->
        case String.trim(output) |> String.split(" ") do
          [width_str, height_str] ->
            case {Integer.parse(width_str), Integer.parse(height_str)} do
              {{width, ""}, {height, ""}} -> {:ok, {width, height}}
              _ -> {:error, "Invalid dimensions format"}
            end

          _ ->
            {:error, "Unexpected identify output format"}
        end

      {error_output, _exit_code} ->
        {:error, "ImageMagick identify failed: #{error_output}"}
    end
  rescue
    e -> {:error, "System command failed: #{Exception.message(e)}"}
  end

  defp upload_local(%Plug.Upload{} = upload, user_id) do
    uploads_dir = get_config(:uploads_dir) || "priv/static/uploads"
    avatars_dir = Path.join(uploads_dir, "avatars")

    # Create directory if it doesn't exist
    File.mkdir_p!(avatars_dir)

    # Generate unique filename
    filename = "#{user_id}_#{System.unique_integer([:positive])}_#{upload.filename}"
    filepath = Path.join(avatars_dir, filename)

    # Copy uploaded file to permanent location
    case File.cp(upload.path, filepath) do
      :ok ->
        {:ok, "/uploads/avatars/#{filename}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upload_s3(%Plug.Upload{} = upload, user_id) do
    bucket = get_config(:bucket)

    # Generate unique S3 key
    filename = "#{user_id}_#{System.unique_integer([:positive])}_#{upload.filename}"
    key = "avatars/#{filename}"

    # Read file content
    case File.read(upload.path) do
      {:ok, file_content} ->
        # Upload to S3
        case ExAws.S3.put_object(bucket, key, file_content, [
               {:content_type, upload.content_type || "image/jpeg"},
               {:acl, :public_read}
             ])
             |> ExAws.request() do
          {:ok, _response} ->
            # Return public Backblaze B2 URL
            endpoint = get_config(:endpoint) || "s3.us-west-002.backblazeb2.com"
            url = "https://#{bucket}.#{endpoint}/#{key}"
            {:ok, url}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes an avatar file from storage.

  Takes the full URL and extracts the necessary information to delete the file.
  """
  def delete_avatar(nil), do: :ok
  def delete_avatar(""), do: :ok

  def delete_avatar(url) when is_binary(url) do
    case get_config(:adapter) do
      :local -> delete_local(url)
      :s3 -> delete_s3(url)
    end
  end

  defp delete_local(url) do
    # Extract filename from URL like "/uploads/avatars/filename.jpg"
    case String.split(url, "/") do
      [_, "uploads", "avatars", filename] ->
        uploads_dir = get_config(:uploads_dir) || "priv/static/uploads"
        filepath = Path.join([uploads_dir, "avatars", filename])
        File.rm(filepath)

      _ ->
        {:error, :invalid_url}
    end
  end

  defp delete_s3(url) do
    bucket = get_config(:bucket)

    # Extract S3 key from URL
    # URL format: https://bucket.s3.region.amazonaws.com/avatars/filename.jpg
    case extract_s3_key_from_url(url) do
      {:ok, key} ->
        case ExAws.S3.delete_object(bucket, key) |> ExAws.request() do
          {:ok, _response} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_s3_key_from_url(url) do
    # Parse URL like https://bucket.s3.us-west-002.backblazeb2.com/avatars/filename.jpg
    # or https://bucket.s3.region.amazonaws.com/avatars/filename.jpg
    uri = URI.parse(url)

    case uri.path do
      "/" <> path -> {:ok, path}
      _ -> {:error, :invalid_s3_url}
    end
  end

  @doc """
  Returns the public URL for an avatar.

  The avatar value could be a filename or a full URL depending on storage adapter.
  """
  def avatar_url(nil), do: nil
  def avatar_url(""), do: nil

  def avatar_url(avatar) when is_binary(avatar) do
    case get_config(:adapter) do
      :local ->
        # For local storage, if it's already a URL path, return as-is
        # If it's just a filename, prepend the path
        if String.starts_with?(avatar, "/") do
          avatar
        else
          "/uploads/avatars/#{avatar}"
        end

      :s3 ->
        # For S3, if it's already a full URL, return as-is
        # If it's just a key/filename, construct the full URL
        if String.starts_with?(avatar, "http") do
          avatar
        else
          bucket = get_config(:bucket)
          endpoint = get_config(:endpoint) || "s3.us-west-002.backblazeb2.com"
          "https://#{bucket}.#{endpoint}/avatars/#{avatar}"
        end
    end
  end

  defp get_config(key) do
    Application.get_env(:elektrine, :uploads, []) |> Keyword.get(key)
  end
end
