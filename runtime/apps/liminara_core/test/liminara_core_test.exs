defmodule LiminaraCoreTest do
  use ExUnit.Case

  describe "version/0" do
    test "returns a version string" do
      assert is_binary(LiminaraCore.version())
    end

    test "matches SemVer format" do
      version = LiminaraCore.version()
      assert version =~ ~r/^\d+\.\d+\.\d+$/
    end
  end
end
