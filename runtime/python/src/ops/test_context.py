def execute(inputs, context=None):
    context = context or {}

    return {
        "outputs": {
            "run_id": context.get("run_id", ""),
            "started_at": context.get("started_at", ""),
            "replay_of_run_id": context.get("replay_of_run_id") or "",
            "text": inputs.get("text", ""),
        }
    }
