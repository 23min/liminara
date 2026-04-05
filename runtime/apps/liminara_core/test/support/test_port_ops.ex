defmodule Liminara.TestPortOps.PureReverse do
  @behaviour Liminara.Op

  def name, do: "test_reverse"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "test_reverse"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.Recordable do
  @behaviour Liminara.Op

  def name, do: "test_recordable"
  def version, do: "1.0"
  def determinism, do: :recordable
  def executor, do: :port
  def python_op, do: "test_recordable"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.SideEffect do
  @behaviour Liminara.Op

  def name, do: "test_side_effect"
  def version, do: "1.0"
  def determinism, do: :side_effecting
  def executor, do: :port
  def python_op, do: "test_side_effect"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.PureEcho do
  @behaviour Liminara.Op

  def name, do: "echo"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "echo"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.Fail do
  @behaviour Liminara.Op

  def name, do: "test_raise"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "test_raise"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.Warning do
  @behaviour Liminara.Op

  def name, do: "test_warning"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "test_warning"

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.WithTimeoutExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.ExecutionSpec

  def name, do: "legacy_port_timeout"
  def version, do: "0.0.1"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "echo"

  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "port_timeout_spec", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{executor: :port, entrypoint: "test_sleep", timeout_ms: 50},
      contracts: %{
        outputs: %{},
        decisions: %{may_emit: false},
        warnings: %{may_emit: false}
      }
    })
  end

  def execute(_inputs), do: raise("should not be called inline")
end

defmodule Liminara.TestPortOps.WithRuntimeContext do
  @behaviour Liminara.Op

  alias Liminara.ExecutionSpec

  def name, do: "legacy_port_context"
  def version, do: "0.0.1"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "echo"

  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "port_runtime_context", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{
        executor: :port,
        entrypoint: "test_context",
        requires_execution_context: true
      },
      contracts: %{
        outputs: %{
          run_id: :artifact,
          started_at: :artifact,
          replay_of_run_id: :artifact,
          text: :artifact
        }
      }
    })
  end

  def execute(_inputs), do: raise("should not be called inline")
end
