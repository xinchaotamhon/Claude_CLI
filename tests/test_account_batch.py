import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

from verify_account_batch import (  # noqa: E402
    EXIT_CONTRACT,
    EXIT_OK,
    ContractError,
    validate_document,
)


EXAMPLE = Path(__file__).resolve().parents[1] / "router_challenger" / "account-batch.example.json"


class AccountBatchContractTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads(EXAMPLE.read_text(encoding="utf-8"))

    def slot(self, slot_id):
        return next(slot for slot in self.document["slots"] if slot["id"] == slot_id)

    def assert_invalid(self, document):
        with self.assertRaises(ContractError):
            validate_document(document)

    def test_example_is_valid_and_contains_exactly_seven_expected_slots(self):
        validate_document(self.document)
        self.assertEqual(
            {slot["id"] for slot in self.document["slots"]},
            {
                "codex_free_1",
                "codex_free_2",
                "codex_free_3",
                "codex_plus_1",
                "google_pro_1",
                "google_pro_2",
                "google_pro_3",
            },
        )
        self.assertEqual([slot["login_order"] for slot in self.document["slots"]], [1, 2, 3, 4, 5, 6, 7])

    def test_onboarding_disables_automatic_fallback_by_default(self):
        self.assertIs(self.document["automatic_fallback_default"], False)
        invalid = deepcopy(self.document)
        invalid["automatic_fallback_default"] = True
        self.assert_invalid(invalid)

    def test_codex_free_and_plus_models_are_exact(self):
        self.assertEqual(self.slot("codex_free_1")["allowed_models"], ["terra", "luna"])
        self.assertEqual(self.slot("codex_free_2")["allowed_models"], ["terra", "luna"])
        self.assertEqual(self.slot("codex_free_3")["allowed_models"], ["terra", "luna"])
        self.assertEqual(self.slot("codex_plus_1")["allowed_models"], ["sol", "terra", "luna"])
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "codex_free_1")["allowed_models"] = ["sol", "terra", "luna"]
        self.assert_invalid(invalid)

    def test_google_pro_has_two_independent_usage_groups_for_each_slot(self):
        for slot_id in ("google_pro_1", "google_pro_2", "google_pro_3"):
            self.assertEqual(self.slot(slot_id)["usage_groups"], ["gemini_models", "claude_gpt_models"])
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "google_pro_1")["usage_groups"] = ["gemini_models"]
        self.assert_invalid(invalid)

    def test_duplicate_slot_ids_are_rejected(self):
        invalid = deepcopy(self.document)
        invalid["slots"][1]["id"] = "codex_free_1"
        self.assert_invalid(invalid)

    def test_duplicate_labels_are_rejected_case_insensitively(self):
        invalid = deepcopy(self.document)
        invalid["slots"][1]["label"] = "CODEX_FREE_1"
        self.assert_invalid(invalid)

    def test_unknown_provider_and_plan_are_rejected(self):
        invalid = deepcopy(self.document)
        invalid["slots"][0]["provider"] = "other"
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        invalid["slots"][0]["expected_plan"] = "enterprise"
        self.assert_invalid(invalid)

    def test_plan_provider_and_slot_binding_cannot_be_changed(self):
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "codex_plus_1")["expected_plan"] = "codex_free"
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "google_pro_1")["provider"] = "openai_codex"
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "google_pro_1")["login_order"] = 1
        self.assert_invalid(invalid)

    def test_wrong_slot_count_or_unknown_slot_is_rejected(self):
        invalid = deepcopy(self.document)
        invalid["slots"].pop()
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        invalid["slots"][-1]["id"] = "google_pro_4"
        self.assert_invalid(invalid)

    def test_secret_shaped_fields_are_rejected_at_any_depth(self):
        invalid = deepcopy(self.document)
        invalid["api_key"] = "not-allowed"
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        invalid["extensions"]["oauthToken"] = "not-allowed"
        self.assert_invalid(invalid)

    def test_unknown_fields_and_incorrect_provider_specific_shape_are_rejected(self):
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "codex_free_1")["usage_groups"] = ["gemini_models"]
        self.assert_invalid(invalid)
        invalid = deepcopy(self.document)
        self.slot_from(invalid, "google_pro_1")["allowed_models"] = ["terra"]
        self.assert_invalid(invalid)

    def test_cli_returns_expected_exit_codes(self):
        valid = subprocess.run(
            [sys.executable, str(TOOLS / "verify_account_batch.py"), str(EXAMPLE), "--quiet"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(valid.returncode, EXIT_OK, valid.stderr)
        invalid = deepcopy(self.document)
        invalid["automatic_fallback_default"] = True
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "invalid.json"
            path.write_text(json.dumps(invalid), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(TOOLS / "verify_account_batch.py"), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, EXIT_CONTRACT)
        self.assertIn("CONTRACT ERROR", result.stderr)

    @staticmethod
    def slot_from(document, slot_id):
        return next(slot for slot in document["slots"] if slot["id"] == slot_id)


if __name__ == "__main__":
    unittest.main()
