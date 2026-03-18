defmodule Liminara.Artifact.Store do
  @moduledoc """
  Content-addressed blob storage on the filesystem.

  Artifacts are stored in Git-style sharded directories:
  `{store_root}/{hex[0:2]}/{hex[2:4]}/{hex}`

  Identity is `sha256(raw_bytes)`. Writes are idempotent — storing the
  same content twice produces one file.
  """

  alias Liminara.Hash

  @doc """
  Store content and return its hash.

  Returns `{:ok, "sha256:{hex}"}`. Idempotent — skips write if blob exists.
  """
  @spec put(Path.t(), binary()) :: {:ok, String.t()}
  def put(store_root, content) when is_binary(content) do
    hash = Hash.hash_bytes(content)
    path = blob_path(store_root, hash)

    unless File.exists?(path) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    {:ok, hash}
  end

  @doc """
  Read content by hash.

  Returns `{:ok, binary}` or `{:error, :not_found}`.
  """
  @spec get(Path.t(), String.t()) :: {:ok, binary()} | {:error, :not_found}
  def get(store_root, hash) do
    path = blob_path(store_root, hash)

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  @doc """
  Check if an artifact exists on disk.
  """
  @spec exists?(Path.t(), String.t()) :: boolean()
  def exists?(store_root, hash) do
    store_root |> blob_path(hash) |> File.exists?()
  end

  defp blob_path(store_root, hash) do
    hex = String.replace_prefix(hash, "sha256:", "")
    Path.join([store_root, String.slice(hex, 0, 2), String.slice(hex, 2, 2), hex])
  end
end
