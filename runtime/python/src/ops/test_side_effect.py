"""Test side-effecting op — simulates writing to an external system."""


def execute(inputs):
    data = inputs.get("data", "")
    return {"outputs": {"result": f"side_effect_done:{data}"}}
