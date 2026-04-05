def execute(inputs):
    return {
        "outputs": {"result": inputs.get("text", "")},
        "warnings": [
            {
                "code": "python_warning",
                "severity": "medium",
                "summary": "warning from python",
                "details": "extra warning metadata",
            }
        ],
    }
