"""Test pure op — reverses a string. Deterministic, cacheable."""


def execute(inputs):
    text = inputs.get("text", "")
    return {"outputs": {"result": text[::-1]}}
