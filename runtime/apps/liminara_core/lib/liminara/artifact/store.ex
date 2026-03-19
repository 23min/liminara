defmodule Liminara.Artifact.Store do
  @moduledoc """
  Content-addressed blob storage on the filesystem.

  Artifacts are stored in Git-style sharded directories:
  `{store_root}/{hex[0:2]}/{hex[2:4]}/{hex}`

  Identity is `sha256(raw_bytes)`. Writes are idempotent — storing the
  same content twice produces one file.

  Can be used in two modes:
  - **Supervised** (arity-1 functions): calls go through the named GenServer
    which holds the store_root. Used when the OTP application is running.
  - **Direct** (arity-2 functions with explicit store_root): stateless,
    used in tests or standalone scripts.
  """

  use GenServer

  alias Liminara.Hash

  # ── Supervised API (process-backed) ─────────────────────────────

  def start_link(opts) do
    store_root = Keyword.fetch!(opts, :store_root)
    GenServer.start_link(__MODULE__, store_root, name: __MODULE__)
  end

  @doc "Store content via the supervised process. Returns `{:ok, hash}`."
  @spec put(binary()) :: {:ok, String.t()}
  def put(content) when is_binary(content) do
    GenServer.call(__MODULE__, {:put, content})
  end

  @doc "Read content by hash via the supervised process."
  @spec get(String.t()) :: {:ok, binary()} | {:error, :not_found}
  def get(hash) when is_binary(hash) do
    GenServer.call(__MODULE__, {:get, hash})
  end

  @doc "Check if an artifact exists via the supervised process."
  @spec exists?(String.t()) :: boolean()
  def exists?(hash) when is_binary(hash) do
    GenServer.call(__MODULE__, {:exists?, hash})
  end

  # ── Direct API (stateless, explicit store_root) ─────────────────

  @doc """
  Store content and return its hash.

  Returns `{:ok, "sha256:{hex}"}`. Idempotent — skips write if blob exists.
  """
  @spec put(Path.t(), binary()) :: {:ok, String.t()}
  def put(store_root, content) when is_binary(store_root) and is_binary(content) do
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

  # ── GenServer callbacks ─────────────────────────────────────────

  @impl true
  def init(store_root) do
    File.mkdir_p!(store_root)
    {:ok, %{store_root: store_root}}
  end

  @impl true
  def handle_call({:put, content}, _from, %{store_root: root} = state) do
    {:reply, put(root, content), state}
  end

  def handle_call({:get, hash}, _from, %{store_root: root} = state) do
    {:reply, get(root, hash), state}
  end

  def handle_call({:exists?, hash}, _from, %{store_root: root} = state) do
    {:reply, exists?(root, hash), state}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp blob_path(store_root, hash) do
    hex = String.replace_prefix(hash, "sha256:", "")
    Path.join([store_root, String.slice(hex, 0, 2), String.slice(hex, 2, 2), hex])
  end
end
