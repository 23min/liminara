defmodule Liminara.ExecutionContractStructsTest do
  use ExUnit.Case, async: true

  alias Liminara.{ExecutionContext, ExecutionSpec, OpResult, Warning}

  test "ExecutionSpec has canonical section defaults" do
    spec = ExecutionSpec.new()

    assert %ExecutionSpec.Identity{} = spec.identity
    assert %ExecutionSpec.Determinism{} = spec.determinism
    assert %ExecutionSpec.Execution{} = spec.execution
    assert %ExecutionSpec.Isolation{} = spec.isolation
    assert %ExecutionSpec.Contracts{} = spec.contracts

    assert spec.determinism.class == nil
    assert spec.determinism.cache_policy == nil
    assert spec.determinism.replay_policy == nil
    assert spec.execution.executor == nil
    assert spec.execution.entrypoint == nil
    assert spec.execution.timeout_ms == nil
    assert spec.execution.requires_execution_context == false
    assert spec.isolation.env_vars == []
    assert spec.isolation.network == :none
    assert spec.contracts.inputs == %{}
    assert spec.contracts.outputs == %{}
    assert spec.contracts.decisions == %{may_emit: false}
    assert spec.contracts.warnings == %{may_emit: false}
  end

  test "ExecutionSpec normalizes nested section maps into canonical structs" do
    spec =
      ExecutionSpec.new(%{
        identity: %{name: "radar_summarize", version: "0.1.0"},
        determinism: %{
          class: :recordable,
          cache_policy: :content_addressed,
          replay_policy: :replay_required
        },
        execution: %{
          executor: :port,
          entrypoint: "radar_summarize",
          timeout_ms: 30_000,
          requires_execution_context: true
        },
        isolation: %{
          env_vars: ["ANTHROPIC_API_KEY"],
          network: :tcp_outbound,
          bootstrap_read_paths: [:op_code, :runtime_deps],
          runtime_read_paths: [],
          runtime_write_paths: []
        },
        contracts: %{
          inputs: %{items: :artifact},
          outputs: %{summary: :artifact},
          decisions: %{may_emit: true},
          warnings: %{may_emit: true}
        }
      })

    assert %ExecutionSpec.Identity{name: "radar_summarize", version: "0.1.0"} = spec.identity

    assert %ExecutionSpec.Determinism{
             class: :recordable,
             cache_policy: :content_addressed,
             replay_policy: :replay_required
           } = spec.determinism

    assert %ExecutionSpec.Execution{
             executor: :port,
             entrypoint: "radar_summarize",
             timeout_ms: 30_000,
             requires_execution_context: true
           } = spec.execution

    assert %ExecutionSpec.Isolation{
             env_vars: ["ANTHROPIC_API_KEY"],
             network: :tcp_outbound,
             bootstrap_read_paths: [:op_code, :runtime_deps],
             runtime_read_paths: [],
             runtime_write_paths: []
           } = spec.isolation

    assert %ExecutionSpec.Contracts{
             inputs: %{items: :artifact},
             outputs: %{summary: :artifact},
             decisions: %{may_emit: true},
             warnings: %{may_emit: true}
           } = spec.contracts
  end

  test "OpResult defaults to empty decisions and warnings" do
    result = %OpResult{}

    assert result.outputs == %{}
    assert result.decisions == []
    assert result.warnings == []
  end

  test "Warning supports affected_outputs list" do
    warning = %Warning{code: "radar_placeholder_summary", severity: :degraded}

    assert warning.code == "radar_placeholder_summary"
    assert warning.severity == :degraded
    assert warning.affected_outputs == []
  end

  describe "Warning.new/1" do
    test "builds a canonical struct from all fields" do
      warning =
        Warning.new(%{
          code: "radar_placeholder_summary",
          severity: :degraded,
          summary: "placeholder summary used because ANTHROPIC_API_KEY is missing",
          cause: "missing_api_key",
          remediation: "configure ANTHROPIC_API_KEY",
          affected_outputs: ["summary"]
        })

      assert %Warning{
               code: "radar_placeholder_summary",
               severity: :degraded,
               summary: "placeholder summary used because ANTHROPIC_API_KEY is missing",
               cause: "missing_api_key",
               remediation: "configure ANTHROPIC_API_KEY",
               affected_outputs: ["summary"]
             } = warning
    end

    test "accepts a keyword list" do
      warning =
        Warning.new(
          code: "low_signal",
          severity: :low,
          summary: "fewer sources than expected"
        )

      assert warning.code == "low_signal"
      assert warning.severity == :low
      assert warning.summary == "fewer sources than expected"
      assert warning.affected_outputs == []
      assert warning.cause == nil
      assert warning.remediation == nil
    end

    test "defaults affected_outputs to [] when omitted" do
      warning =
        Warning.new(%{
          code: "low_signal",
          severity: :info,
          summary: "test"
        })

      assert warning.affected_outputs == []
    end

    test "accepts every locked severity atom" do
      for severity <- [:info, :low, :medium, :high, :degraded] do
        warning = Warning.new(%{code: "c", severity: severity, summary: "s"})
        assert warning.severity == severity
      end
    end

    test "raises ArgumentError when code is missing" do
      assert_raise ArgumentError, ~r/code/, fn ->
        Warning.new(%{severity: :low, summary: "s"})
      end
    end

    test "raises ArgumentError when severity is missing" do
      assert_raise ArgumentError, ~r/severity/, fn ->
        Warning.new(%{code: "c", summary: "s"})
      end
    end

    test "raises ArgumentError when summary is missing" do
      assert_raise ArgumentError, ~r/summary/, fn ->
        Warning.new(%{code: "c", severity: :low})
      end
    end

    test "raises ArgumentError when code is not a binary" do
      assert_raise ArgumentError, ~r/code/, fn ->
        Warning.new(%{code: :atom_code, severity: :low, summary: "s"})
      end
    end

    test "raises ArgumentError when summary is not a binary" do
      assert_raise ArgumentError, ~r/summary/, fn ->
        Warning.new(%{code: "c", severity: :low, summary: 42})
      end
    end

    test "raises ArgumentError when severity is outside the locked taxonomy" do
      assert_raise ArgumentError, ~r/severity/, fn ->
        Warning.new(%{code: "c", severity: :fatal, summary: "s"})
      end
    end

    test "raises ArgumentError when severity is a binary (not an atom)" do
      assert_raise ArgumentError, ~r/severity/, fn ->
        Warning.new(%{code: "c", severity: "low", summary: "s"})
      end
    end

    test "raises ArgumentError when affected_outputs is not a list" do
      assert_raise ArgumentError, ~r/affected_outputs/, fn ->
        Warning.new(%{code: "c", severity: :low, summary: "s", affected_outputs: "summary"})
      end
    end

    test "raises ArgumentError when affected_outputs has non-binary entries" do
      assert_raise ArgumentError, ~r/affected_outputs/, fn ->
        Warning.new(%{code: "c", severity: :low, summary: "s", affected_outputs: [:summary]})
      end
    end

    test "raises ArgumentError when cause is not a binary or nil" do
      assert_raise ArgumentError, ~r/cause/, fn ->
        Warning.new(%{code: "c", severity: :low, summary: "s", cause: 123})
      end
    end

    test "accepts cause explicitly set to nil" do
      warning = Warning.new(%{code: "c", severity: :low, summary: "s", cause: nil})
      assert warning.cause == nil
    end

    test "raises ArgumentError when remediation is not a binary or nil" do
      assert_raise ArgumentError, ~r/remediation/, fn ->
        Warning.new(%{code: "c", severity: :low, summary: "s", remediation: :retry})
      end
    end

    test "raises ArgumentError on unknown keys" do
      assert_raise ArgumentError, ~r/unknown/i, fn ->
        Warning.new(%{code: "c", severity: :low, summary: "s", rogue_field: "x"})
      end
    end

    test "exposes the locked severity taxonomy via severities/0" do
      assert Warning.severities() == [:info, :low, :medium, :high, :degraded]
    end
  end

  describe "Warning.enforce_contract/2" do
    test "returns [] unchanged regardless of may_emit" do
      assert Warning.enforce_contract([], true) == []
      assert Warning.enforce_contract([], false) == []
    end

    test "passes warnings through unchanged when may_emit? is true" do
      warnings = [
        Warning.new(%{code: "w1", severity: :low, summary: "first"}),
        Warning.new(%{code: "w2", severity: :medium, summary: "second"})
      ]

      assert Warning.enforce_contract(warnings, true) == warnings
    end

    test "prepends a canonical violation warning when may_emit? is false and warnings are non-empty" do
      warnings = [
        Warning.new(%{code: "disallowed", severity: :low, summary: "nope"})
      ]

      result = Warning.enforce_contract(warnings, false)

      assert length(result) == 2
      [violation | rest] = result

      assert %Warning{
               code: "op_warning_contract_violation",
               severity: :high,
               cause: "may_emit_false"
             } = violation

      assert violation.summary =~ "codes: disallowed"
      assert rest == warnings
    end

    test "violation summary omits the codes list when no code can be extracted" do
      # Atom-keyed maps without `code` and exotic values both exercise the
      # non-matching clauses of warning_code/1, producing nil codes that are
      # rejected from the summary.
      warnings = [%{summary: "no code here"}, :odd_value]

      result = Warning.enforce_contract(warnings, false)

      assert [violation | _rest] = result
      assert violation.code == "op_warning_contract_violation"
      refute violation.summary =~ "codes:"
      assert violation.summary =~ "2 warning(s)"
    end

    test "extracts codes from atom-keyed maps and string-keyed maps" do
      warnings = [
        %{code: "atom_code", severity: :low, summary: "atom-keyed"},
        %{"code" => "string_code", "severity" => "low", "summary" => "string-keyed"}
      ]

      result = Warning.enforce_contract(warnings, false)
      [violation | _rest] = result

      assert violation.summary =~ "atom_code"
      assert violation.summary =~ "string_code"
    end
  end

  describe "Executor.Port.normalize_warning/1" do
    alias Liminara.Executor.Port, as: ExecutorPort

    test "normalizes a canonical binary-keyed map using Warning.new/1" do
      warning =
        ExecutorPort.normalize_warning(%{
          "code" => "python_warning",
          "severity" => "medium",
          "summary" => "warning from python",
          "details" => "extra warning metadata"
        })

      assert %Warning{
               code: "python_warning",
               severity: :medium,
               summary: "warning from python"
             } = warning
    end

    test "passes through an existing %Warning{} struct" do
      canonical =
        Warning.new(%{code: "existing", severity: :low, summary: "already canonical"})

      assert ExecutorPort.normalize_warning(canonical) == canonical
    end

    test "raises ArgumentError when severity string is outside the taxonomy" do
      assert_raise ArgumentError, ~r/severity/, fn ->
        ExecutorPort.normalize_warning(%{
          "code" => "bad",
          "severity" => "catastrophic",
          "summary" => "unknown severity should be rejected"
        })
      end
    end

    test "raises ArgumentError when required fields are missing from a Python payload" do
      assert_raise ArgumentError, fn ->
        ExecutorPort.normalize_warning(%{"code" => "bad", "severity" => "low"})
      end
    end

    test "coerces every locked severity string to its atom" do
      for {severity_string, severity_atom} <- [
            {"info", :info},
            {"low", :low},
            {"medium", :medium},
            {"high", :high},
            {"degraded", :degraded}
          ] do
        warning =
          ExecutorPort.normalize_warning(%{
            "code" => "c",
            "severity" => severity_string,
            "summary" => "s"
          })

        assert warning.severity == severity_atom,
               "expected #{severity_string} -> #{severity_atom}, got #{inspect(warning.severity)}"
      end
    end

    test "accepts atom-keyed maps (pass-through of normalize_warning_key atom clause)" do
      warning =
        ExecutorPort.normalize_warning(%{
          code: "atom_code",
          severity: :info,
          summary: "atom-keyed ok"
        })

      assert %Warning{code: "atom_code", severity: :info, summary: "atom-keyed ok"} = warning
    end
  end

  test "ExecutionContext carries runtime identity fields" do
    context =
      %ExecutionContext{
        run_id: "run_123",
        started_at: "2026-04-03T12:00:00Z",
        pack_id: "radar",
        pack_version: "0.1.0"
      }

    assert context.run_id == "run_123"
    assert context.started_at == "2026-04-03T12:00:00Z"
    assert context.pack_id == "radar"
    assert context.pack_version == "0.1.0"
    assert context.replay_of_run_id == nil
    assert context.topic_id == nil
  end
end
