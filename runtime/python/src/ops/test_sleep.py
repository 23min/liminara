"""Test op that sleeps forever — used to test timeout handling."""

import time


def execute(inputs):
    time.sleep(3600)
    return {"outputs": {}}
