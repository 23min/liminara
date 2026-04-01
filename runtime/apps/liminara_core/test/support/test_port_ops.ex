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
