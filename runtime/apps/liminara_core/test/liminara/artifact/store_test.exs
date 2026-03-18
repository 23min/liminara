defmodule Liminara.Artifact.StoreTest do
  use ExUnit.Case, async: true

  alias Liminara.Artifact.Store
  alias Liminara.Hash

  @fixtures_dir Path.expand("../../../../../../test_fixtures/golden_run", __DIR__)

  setup do
    # Each test gets a unique temp directory
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_artifact_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{store_root: tmp}
  end

  describe "put/2 and get/2 round-trip" do
    test "put returns a sha256 hash, get returns original bytes", %{store_root: root} do
      content = "hello world"
      {:ok, hash} = Store.put(root, content)

      assert hash =~ ~r/^sha256:[a-f0-9]{64}$/
      assert {:ok, ^content} = Store.get(root, hash)
    end

    test "multiple different artifacts stored correctly", %{store_root: root} do
      {:ok, hash1} = Store.put(root, "artifact one")
      {:ok, hash2} = Store.put(root, "artifact two")

      assert hash1 != hash2
      assert {:ok, "artifact one"} = Store.get(root, hash1)
      assert {:ok, "artifact two"} = Store.get(root, hash2)
    end

    test "binary content round-trips", %{store_root: root} do
      content = <<0, 1, 2, 255, 128, 64>>
      {:ok, hash} = Store.put(root, content)
      assert {:ok, ^content} = Store.get(root, hash)
    end
  end

  describe "idempotency" do
    test "put same content twice returns same hash", %{store_root: root} do
      {:ok, hash1} = Store.put(root, "duplicate content")
      {:ok, hash2} = Store.put(root, "duplicate content")
      assert hash1 == hash2
    end

    test "put same content twice creates single file on disk", %{store_root: root} do
      {:ok, _hash} = Store.put(root, "single file")
      {:ok, _hash} = Store.put(root, "single file")

      files =
        root
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      assert length(files) == 1
    end
  end

  describe "directory sharding" do
    test "file stored at {hex[0:2]}/{hex[2:4]}/{hex} path", %{store_root: root} do
      content = "sharding test"
      {:ok, hash} = Store.put(root, content)
      hex = String.replace_prefix(hash, "sha256:", "")

      expected_path =
        Path.join([root, String.slice(hex, 0, 2), String.slice(hex, 2, 2), hex])

      assert File.exists?(expected_path)
    end

    test "known content produces known path", %{store_root: root} do
      # Use golden fixture artifact 1 content to verify path
      artifact1_hash = "sha256:fbebbef195fa31dd9ee877e294bec860f9bfba77abc08f9244c21d5930552521"
      hex = String.replace_prefix(artifact1_hash, "sha256:", "")

      golden_path =
        Path.join([
          @fixtures_dir,
          "artifacts",
          String.slice(hex, 0, 2),
          String.slice(hex, 2, 2),
          hex
        ])

      content = File.read!(golden_path)

      {:ok, hash} = Store.put(root, content)
      assert hash == artifact1_hash
    end
  end

  describe "golden fixtures" do
    test "reads artifact 1 (JSON documents blob)" do
      hash = "sha256:fbebbef195fa31dd9ee877e294bec860f9bfba77abc08f9244c21d5930552521"
      hex = String.replace_prefix(hash, "sha256:", "")

      path =
        Path.join([
          @fixtures_dir,
          "artifacts",
          String.slice(hex, 0, 2),
          String.slice(hex, 2, 2),
          hex
        ])

      content = File.read!(path)
      assert Hash.hash_bytes(content) == hash
    end

    test "reads artifact 2 (text summary blob)" do
      hash = "sha256:4e5afbaa88a70719617185a517ec4c758976abe93fbd5900d1f57916d8c5c2a5"
      hex = String.replace_prefix(hash, "sha256:", "")

      path =
        Path.join([
          @fixtures_dir,
          "artifacts",
          String.slice(hex, 0, 2),
          String.slice(hex, 2, 2),
          hex
        ])

      content = File.read!(path)
      assert Hash.hash_bytes(content) == hash
    end

    test "round-trip through store matches golden fixture", %{store_root: root} do
      hash = "sha256:fbebbef195fa31dd9ee877e294bec860f9bfba77abc08f9244c21d5930552521"
      hex = String.replace_prefix(hash, "sha256:", "")

      golden_path =
        Path.join([
          @fixtures_dir,
          "artifacts",
          String.slice(hex, 0, 2),
          String.slice(hex, 2, 2),
          hex
        ])

      original = File.read!(golden_path)
      {:ok, stored_hash} = Store.put(root, original)
      {:ok, retrieved} = Store.get(root, stored_hash)

      assert stored_hash == hash
      assert retrieved == original
    end
  end

  describe "edge cases" do
    test "empty content", %{store_root: root} do
      {:ok, hash} = Store.put(root, "")
      assert hash =~ ~r/^sha256:[a-f0-9]{64}$/
      assert {:ok, ""} = Store.get(root, hash)
    end

    test "get non-existent hash returns error", %{store_root: root} do
      assert {:error, :not_found} =
               Store.get(
                 root,
                 "sha256:0000000000000000000000000000000000000000000000000000000000000000"
               )
    end

    test "exists? returns true after put", %{store_root: root} do
      {:ok, hash} = Store.put(root, "exists test")
      assert Store.exists?(root, hash)
    end

    test "exists? returns false for unknown hash", %{store_root: root} do
      refute Store.exists?(
               root,
               "sha256:0000000000000000000000000000000000000000000000000000000000000000"
             )
    end
  end
end
