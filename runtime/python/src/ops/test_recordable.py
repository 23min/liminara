"""Test recordable op — simulates an LLM call that returns a decision."""


def execute(inputs):
    prompt = inputs.get("prompt", "")
    response = f"Generated response for: {prompt}"
    decision = {
        "decision_type": "llm_response",
        "inputs": {"prompt": prompt},
        "output": {"response": response},
    }
    return {
        "outputs": {"result": response},
        "decisions": [decision],
    }
