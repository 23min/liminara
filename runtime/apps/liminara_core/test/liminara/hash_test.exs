defmodule Liminara.HashTest do
  use ExUnit.Case, async: true

  alias Liminara.Hash

  describe "hash_bytes/1" do
    test "returns sha256:{64 hex chars} format" do
      result = Hash.hash_bytes("test")
      assert result =~ ~r/^sha256:[a-f0-9]{64}$/
    end

    test "known input produces known hash" do
      # SHA-256 of "test" is well-known
      assert Hash.hash_bytes("test") ==
               "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    end

    test "accepts binary input" do
      result = Hash.hash_bytes(<<0, 1, 2, 3>>)
      assert result =~ ~r/^sha256:[a-f0-9]{64}$/
    end
  end

  describe "hash_event/4" do
    test "matches hand-computed hash for the first golden fixture event" do
      # First event from events.jsonl — run_started
      event_type = "run_started"

      payload = %{
        "pack_id" => "test_pack",
        "pack_version" => "0.1.0",
        "plan_hash" => "sha256:a06ae00fd7ccbf735f9047db048bda690f2f8a747dbb78b13deb1c91d4ba7a5d",
        "run_id" => "test_pack-20260315T120000-aabbccdd"
      }

      prev_hash = nil
      timestamp = "2026-03-15T12:00:00.000Z"

      assert Hash.hash_event(event_type, payload, prev_hash, timestamp) ==
               "sha256:e4274adb96b1ba7c46effc7c30a0350ac42eaeeaffa3b8cb01421e7b4e27066a"
    end
  end

  describe "hash_decision/1" do
    test "matches hand-computed hash for the golden fixture decision" do
      record = %{
        "decision_type" => "llm_response",
        "inputs" => %{
          "model_id" => "claude-sonnet-4-6",
          "model_version" => "20251001",
          "prompt_hash" =>
            "sha256:fbebbef195fa31dd9ee877e294bec860f9bfba77abc08f9244c21d5930552521",
          "temperature" => 0.7
        },
        "node_id" => "summarize",
        "op_id" => "summarize_text",
        "op_version" => "1.0",
        "output" => %{
          "response_hash" =>
            "sha256:4e5afbaa88a70719617185a517ec4c758976abe93fbd5900d1f57916d8c5c2a5",
          "token_usage" => %{"input" => 1024, "output" => 512}
        },
        "recorded_at" => "2026-03-15T12:00:04.500Z"
      }

      assert Hash.hash_decision(record) ==
               "sha256:3dcfb329aac2f7f9e1d19c2635a16e269acc1160d5aa9e399a604c5265caf67d"
    end
  end
end
