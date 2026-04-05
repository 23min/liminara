defmodule Liminara.TestOps.Upcase do
  @behaviour Liminara.Op

  @impl true
  def name, do: "upcase"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    {:ok, %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.Concat do
  @behaviour Liminara.Op

  @impl true
  def name, do: "concat"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"a" => a, "b" => b}) do
    {:ok, %{"result" => a <> b}}
  end
end

defmodule Liminara.TestOps.Fail do
  @behaviour Liminara.Op

  @impl true
  def name, do: "fail"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(_inputs) do
    {:error, :intentional_failure}
  end
end

defmodule Liminara.TestOps.Identity do
  @moduledoc "Pure op that passes input through unchanged. Good for testing pipelines."
  @behaviour Liminara.Op

  @impl true
  def name, do: "identity"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(inputs) do
    {:ok, inputs}
  end
end

defmodule Liminara.TestOps.Reverse do
  @moduledoc "Pure op that reverses a string."
  @behaviour Liminara.Op

  @impl true
  def name, do: "reverse"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    {:ok, %{"result" => String.reverse(text)}}
  end
end

defmodule Liminara.TestOps.Recordable do
  @behaviour Liminara.Op

  @impl true
  def name, do: "recordable_op"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execute(%{"prompt" => prompt}) do
    decision = %{
      "decision_type" => "llm_response",
      "inputs" => %{"prompt" => prompt},
      "output" => %{"response" => "Generated response for: #{prompt}"}
    }

    {:ok, %{"result" => "Generated response for: #{prompt}"}, [decision]}
  end
end

defmodule Liminara.TestOps.SideEffect do
  @moduledoc "Side-effecting op that writes to a file (simulated)."
  @behaviour Liminara.Op

  @impl true
  def name, do: "side_effect"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :side_effecting

  @impl true
  def execute(%{"data" => data}) do
    # Simulate a side effect (in real use: send email, write to external DB, etc.)
    {:ok, %{"result" => "side_effect_done:#{data}"}}
  end
end

defmodule Liminara.TestOps.Slow do
  @moduledoc "Pure op that sleeps before returning. For testing timeouts and mid-run inspection."
  @behaviour Liminara.Op

  @impl true
  def name, do: "slow"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    Process.sleep(500)
    {:ok, %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.WithTaskTimeoutExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.ExecutionSpec

  @impl true
  def name, do: "legacy_task_timeout"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "task_timeout_spec", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{executor: :task, entrypoint: "task_timeout_spec", timeout_ms: 50},
      contracts: %{
        outputs: %{result: :artifact},
        decisions: %{may_emit: false},
        warnings: %{may_emit: false}
      }
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    Process.sleep(1_000)
    {:ok, %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.WithTaskExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.ExecutionSpec

  @impl true
  def name, do: "legacy_task_success"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "task_success_spec", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{executor: :task, entrypoint: "task_success_spec", timeout_ms: 500},
      contracts: %{outputs: %{result: :artifact}}
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    Process.sleep(10)
    {:ok, %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.Raise do
  @moduledoc "Op that raises a RuntimeError. For testing crash handling."
  @behaviour Liminara.Op

  @impl true
  def name, do: "raise"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(_inputs) do
    raise "intentional crash"
  end
end

defmodule Liminara.TestOps.ExitKill do
  @moduledoc "Op that exits with :kill. For testing brutal crash handling."
  @behaviour Liminara.Op

  @impl true
  def name, do: "exit_kill"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(_inputs) do
    Process.exit(self(), :kill)
  end
end

defmodule Liminara.TestOps.WithExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult, Warning}

  @impl true
  def name, do: "legacy_name_should_not_win"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :side_effecting

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "explicit_spec_op", version: "2.1.0"},
      determinism: %{
        class: :pure,
        cache_policy: :content_addressed,
        replay_policy: :reexecute
      },
      execution: %{executor: :inline, entrypoint: "explicit_spec_op", timeout_ms: 1_000},
      contracts: %{
        outputs: %{result: :artifact},
        decisions: %{may_emit: false},
        warnings: %{may_emit: true}
      }
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    %OpResult{
      outputs: %{"result" => String.upcase(text)},
      warnings: [
        %Warning{code: "explicit_warning", severity: :low, summary: "normalized warning"}
      ]
    }
  end
end

defmodule Liminara.TestOps.WithRuntimeContext do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionContext, ExecutionSpec, OpResult}

  @impl true
  def name, do: "context_legacy_name"

  @impl true
  def version, do: "1.0.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "runtime_context", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{
        executor: :inline,
        entrypoint: "runtime_context",
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

  @impl true
  def execute(_inputs) do
    raise "runtime context should be injected"
  end

  @impl true
  def execute(%{"text" => text}, %ExecutionContext{} = context) do
    %OpResult{
      outputs: %{
        "run_id" => context.run_id,
        "started_at" => context.started_at,
        "replay_of_run_id" => context.replay_of_run_id,
        "text" => text
      }
    }
  end
end

defmodule Liminara.TestOps.WithOptionalContextHandler do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult}

  @impl true
  def name, do: "optional_context_handler"

  @impl true
  def version, do: "1.0.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "optional_context_handler", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{executor: :inline, entrypoint: "optional_context_handler"},
      contracts: %{outputs: %{mode: :artifact, text: :artifact}}
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    %OpResult{outputs: %{"mode" => "execute_1", "text" => text}}
  end

  @impl true
  def execute(_inputs, _context) do
    raise "execution context should not be injected without requires_execution_context"
  end
end

defmodule Liminara.TestOps.WithWarningMap do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult}

  @impl true
  def name, do: "warning_map_legacy"

  @impl true
  def version, do: "1.0.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "warning_map", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{executor: :inline, entrypoint: "warning_map"},
      contracts: %{
        outputs: %{result: :artifact},
        warnings: %{may_emit: true}
      }
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    %OpResult{
      outputs: %{"result" => String.upcase(text)},
      warnings: [
        %{
          "code" => "inline_warning",
          "severity" => "low",
          "summary" => "warning map from inline op"
        }
      ]
    }
  end
end

defmodule Liminara.TestOps.RecordableWithExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult}

  @impl true
  def name, do: "legacy_recordable_name"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "canonical_recordable_op", version: "2.0.0"},
      determinism: %{class: :recordable, cache_policy: :none, replay_policy: :replay_recorded},
      execution: %{executor: :inline, entrypoint: "canonical_recordable_op"},
      contracts: %{
        outputs: %{result: :artifact},
        decisions: %{may_emit: true}
      }
    })
  end

  @impl true
  def execute(%{"prompt" => prompt}) do
    %OpResult{
      outputs: %{"result" => "Generated response for: #{prompt}"},
      decisions: [
        %{
          "decision_type" => "llm_response",
          "inputs" => %{"prompt" => prompt},
          "output" => %{"response" => "Generated response for: #{prompt}"}
        }
      ]
    }
  end
end

defmodule Liminara.TestOps.RecordableWithRuntimeContextExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionContext, ExecutionSpec, OpResult}

  @impl true
  def name, do: "legacy_recordable_runtime_context"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "recordable_runtime_context", version: "1.0.0"},
      determinism: %{class: :recordable, cache_policy: :none, replay_policy: :replay_recorded},
      execution: %{
        executor: :inline,
        entrypoint: "recordable_runtime_context",
        requires_execution_context: true
      },
      contracts: %{
        outputs: %{run_id: :artifact, started_at: :artifact, text: :artifact},
        decisions: %{may_emit: true}
      }
    })
  end

  @impl true
  def execute(_inputs) do
    raise "runtime context should be injected"
  end

  @impl true
  def execute(%{"text" => text}, %ExecutionContext{} = context) do
    %OpResult{
      outputs: %{
        "run_id" => context.run_id,
        "started_at" => context.started_at,
        "text" => text
      },
      decisions: [
        %{
          "decision_type" => "llm_response",
          "inputs" => %{"text" => text},
          "output" => %{"run_id" => context.run_id}
        }
      ]
    }
  end
end

defmodule Liminara.TestOps.RecordableWithWarningExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult, Warning}

  @impl true
  def name, do: "legacy_recordable_warning"

  @impl true
  def version, do: "0.0.1"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "canonical_recordable_warning_op", version: "2.0.0"},
      determinism: %{class: :recordable, cache_policy: :none, replay_policy: :replay_recorded},
      execution: %{executor: :inline, entrypoint: "canonical_recordable_warning_op"},
      contracts: %{
        outputs: %{result: :artifact},
        decisions: %{may_emit: true},
        warnings: %{may_emit: true}
      }
    })
  end

  @impl true
  def execute(%{"prompt" => prompt}) do
    %OpResult{
      outputs: %{"result" => "Generated response for: #{prompt}"},
      decisions: [
        %{
          "decision_type" => "llm_response",
          "inputs" => %{"prompt" => prompt},
          "output" => %{"response" => "Generated response for: #{prompt}"}
        }
      ],
      warnings: [
        %Warning{
          code: "recordable_warning",
          severity: :low,
          summary: "warning emitted alongside stored decision"
        }
      ]
    }
  end
end

defmodule Liminara.TestOps.WithNoCacheExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult}

  @impl true
  def name, do: "no_cache_legacy"

  @impl true
  def version, do: "1.0.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "no_cache_explicit", version: "1.0.0"},
      determinism: %{class: :pure, cache_policy: :none, replay_policy: :reexecute},
      execution: %{executor: :inline, entrypoint: "no_cache_explicit"},
      contracts: %{outputs: %{result: :artifact}}
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    %OpResult{outputs: %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.WithReplayReexecuteExecutionSpec do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionSpec, OpResult}

  @impl true
  def name, do: "replay_reexecute_legacy"

  @impl true
  def version, do: "1.0.0"

  @impl true
  def determinism, do: :side_effecting

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "replay_reexecute_explicit", version: "1.0.0"},
      determinism: %{class: :side_effecting, cache_policy: :none, replay_policy: :reexecute},
      execution: %{executor: :inline, entrypoint: "replay_reexecute_explicit"},
      contracts: %{outputs: %{result: :artifact}}
    })
  end

  @impl true
  def execute(%{"text" => text}) do
    %OpResult{outputs: %{"result" => String.upcase(text)}}
  end
end
