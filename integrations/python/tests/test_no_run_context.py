"""Tests for no-run-context passthrough behavior.

Spec reference: M-CS-03-decorators.md § No-run-context passthrough

When decorated functions are called outside `with run():`, they execute
normally with zero instrumentation — no events, no files, no errors.
"""

from pathlib import Path

from liminara.decorators import decision, op


class TestOpPassthrough:
    """@op-decorated functions work outside run context."""

    def test_returns_correct_result(self):
        """@op-decorated function returns its result outside run context."""

        @op(name="add", version="1.0", determinism="pure")
        def add(a, b):
            return a + b

        assert add(2, 3) == 5

    def test_with_kwargs(self):
        """@op-decorated function handles kwargs correctly outside run context."""

        @op(name="greet", version="1.0", determinism="pure")
        def greet(name, greeting="hello"):
            return f"{greeting} {name}"

        assert greet("world", greeting="hi") == "hi world"


class TestDecisionPassthrough:
    """@decision-decorated functions work outside run context."""

    def test_returns_correct_result(self):
        """@decision-decorated function returns its result outside run context."""

        @decision(decision_type="stochastic")
        def pick(options):
            return options[0]

        assert pick(["a", "b", "c"]) == "a"


class TestStackedPassthrough:
    """Stacked @op + @decision works outside run context."""

    def test_returns_correct_result(self):
        """Stacked decorators return correct result outside run context."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="llm_response")
        def choose(x):
            return f"chose {x}"

        assert choose("option_a") == "chose option_a"


class TestNoSideEffects:
    """No files or directories created outside run context."""

    def test_no_files_created(self, tmp_path: Path, monkeypatch):
        """No files or directories are created when called outside run context."""
        # Use a clean tmp dir as cwd to detect any file creation
        monkeypatch.chdir(tmp_path)

        @op(name="my_op", version="1.0", determinism="pure")
        @decision(decision_type="stochastic")
        def my_op(x):
            return x

        my_op("test")

        # tmp_path should still be empty
        all_files = list(tmp_path.rglob("*"))
        assert len(all_files) == 0, f"Unexpected files created: {all_files}"

    def test_no_exceptions(self):
        """No exceptions raised for any decorator combination outside run context."""

        @op(name="op1", version="1.0", determinism="pure")
        def op1(x):
            return x

        @decision(decision_type="human_gate")
        def dec1(x):
            return x

        @op(name="op2", version="1.0", determinism="recordable")
        @decision(decision_type="model_selection")
        def stacked(x):
            return x

        # None of these should raise
        op1("a")
        dec1("b")
        stacked("c")


class TestComplexPassthrough:
    """Functions with various signatures pass through correctly."""

    def test_complex_args_and_return(self):
        """Functions with complex args and return values work outside run context."""

        @op(name="transform", version="1.0", determinism="pure")
        def transform(data, multiplier=1, prefix=""):
            return {
                "items": [x * multiplier for x in data],
                "prefix": prefix,
                "count": len(data),
            }

        result = transform([1, 2, 3], multiplier=10, prefix="test")
        assert result == {"items": [10, 20, 30], "prefix": "test", "count": 3}
