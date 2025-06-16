defmodule Elektrine.Uploads do
  @moduledoc """
  Handles file uploads with support for both local storage and S3.
  
  Configuration determines which adapter to use:
  - :local for development (stores files locally)
  - :s3 for production (stores files in S3)
  """

  @doc """
  Uploads a file and returns the public URL.
  
  Returns {:ok, url} on success or {:error, reason} on failure.
  """
  def upload_avatar(%Plug.Upload{} = upload, user_id) do
    case get_config(:adapter) do
      :local -> upload_local(upload, user_id)
      :s3 -> upload_s3(upload, user_id)
    end
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
        ]) |> ExAws.request() do
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