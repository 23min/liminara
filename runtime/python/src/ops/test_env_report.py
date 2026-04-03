"""Test op that reports the child process environment variables."""

import json
import os


def execute(inputs):
    env = dict(os.environ)
    return {"outputs": {"env": json.dumps(env)}}
