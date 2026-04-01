"""Test op that crashes hard — used to test crash detection.
Uses os._exit to bypass all exception handlers."""

import os


def execute(inputs):
    os._exit(42)
