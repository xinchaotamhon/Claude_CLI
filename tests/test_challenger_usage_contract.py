import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

from verify_challenger_usage_contract import (  # noqa: E402
    EXIT_CONTRACT,
    EXIT_OK,
    ContractError,
    validate_document,
)


EXAMPLE = Path(__file__).resolve().parents[1] / "router_challenger" / "usage-contract.example.json"


class ChallengerUsageContractTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads(EXAMPLE.read_text(encoding="utf-8"))

    def test_google_pro_example_has_two_independent_groups(self):
        validate_document(self.document)
        self.assertEqual(
            set(self.document["usage_groups"]),
            {"gemini_models", "claude_gpt_models"},
        )
        for group in self.document["usage_groups"].values():
            self.assertIn("weekly", group)
            self.assertIn("remaining_percent", group["weekly"])
            self.assertIn("reset_at", group["weekly"])

    def test_five_hour_window_is_optional(self):
        for group in self.document["usage_groups"].values():
            group.pop("five_hour", None)
        validate_document(self.document)

    def test_unknown_window_is_explicit_and_reasoned(self):
        window = self.document["usage_groups"]["gemini_models"]["weekly"]
        window.update(status="unknown", remaining_percent=None, reset_at=None, reason="not exposed")
        validate_document(self.document)

    def test_unavailable_window_requires_null_values_and_reason(self):
        window = self.document["usage_groups"]["claude_gpt_models"]["weekly"]
        window.update(status="unavailable", remaining_percent=None, reset_at=None, reason="provider error")
        validate_document(self.document)
        del window["reason"]
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_google_pro_rejects_missing_or_extra_group(self):
        del self.document["usage_groups"]["gemini_models"]
        with self.assertRaises(ContractError):
            validate_document(self.document)
        self.document = json.loads(EXAMPLE.read_text(encoding="utf-8"))
        self.document["usage_groups"]["other"] = self.document["usage_groups"]["gemini_models"]
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_weekly_window_is_required_for_other_providers_too(self):
        self.document["provider"] = {"id": "deepseek", "kind": "deepseek"}
        self.document["usage_groups"] = {"models": {}}
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_provider_extensions_are_supported(self):
        self.document["provider"] = {"id": "example", "kind": "new_provider"}
        self.document["usage_groups"] = {
            "models": self.document["usage_groups"]["gemini_models"]
        }
        self.document["extensions"] = {"provider_window_name": "weekly"}
        validate_document(self.document)

    def test_secret_shaped_fields_are_rejected(self):
        self.document["extensions"]["api_key"] = "must-not-be-here"
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_cli_returns_contract_exit_code(self):
        invalid = dict(self.document)
        invalid["usage_groups"] = {}
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "invalid.json"
            path.write_text(json.dumps(invalid), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(TOOLS / "verify_challenger_usage_contract.py"), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, EXIT_CONTRACT)
        self.assertIn("CONTRACT ERROR", result.stderr)

    def test_example_cli_returns_success(self):
        result = subprocess.run(
            [sys.executable, str(TOOLS / "verify_challenger_usage_contract.py"), str(EXAMPLE), "--quiet"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, EXIT_OK, result.stderr)


if __name__ == "__main__":
    unittest.main()
