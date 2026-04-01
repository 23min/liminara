"""Echo op — returns inputs as outputs. Used for smoke testing the port executor."""


def execute(inputs):
    return {"outputs": inputs}
