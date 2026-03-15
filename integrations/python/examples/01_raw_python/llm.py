"""LLM abstraction — swap this module to change providers.

Default: Anthropic Claude Haiku. To use a different provider, replace
the call_llm function body. The rest of the pipeline is unchanged.
"""


def call_llm(prompt: str) -> str:
    """Call an LLM with the given prompt and return the response text."""
    import anthropic

    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=300,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.content[0].text
