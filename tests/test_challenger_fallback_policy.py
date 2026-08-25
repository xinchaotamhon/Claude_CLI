import json
import subprocess
import sys
import unittest
from copy import deepcopy
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

from verify_challenger_fallback_policy import (  # noqa: E402
    EXIT_CONTRACT,
    EXIT_OK,
    ContractError,
    eligible_route_ids,
    validate_document,
)


EXAMPLE = (
    Path(__file__).resolve().parents[1]
    / "router_challenger"
    / "fallback-policy.example.json"
)


class ChallengerFallbackPolicyTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads(EXAMPLE.read_text(encoding="utf-8"))

    def groups(self, account_id="google-pro-1"):
        return self.document["accounts"][account_id]["usage_groups"]

    def test_example_is_valid_and_google_pro_has_two_usage_branches(self):
        validate_document(self.document)
        self.assertEqual(
            set(self.groups()),
            {"gemini_models", "claude_gpt_models"},
        )
        self.assertEqual(set(self.document["accounts"]), set(self.document["allowlist"]["account_ids"]))

    def test_weekly_is_required_for_every_group(self):
        del self.groups()["gemini_models"]["weekly"]
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_available_five_hour_window_controls_initial_eligibility(self):
        self.groups("google-pro-2")["gemini_models"]["five_hour"]["remaining_percent"] = 0
        self.assertEqual(eligible_route_ids(self.document), ("claude-gpt-primary", "gemini-secondary"))
        self.groups("google-pro-2")["gemini_models"].pop("five_hour")
        self.assertEqual(
            eligible_route_ids(self.document),
            ("gemini-primary", "claude-gpt-primary", "gemini-secondary"),
        )

    def test_unknown_five_hour_allows_initial_but_reactive_fallback_needs_signal(self):
        self.groups("google-pro-2")["gemini_models"]["five_hour"] = {
            "status": "unknown",
            "remaining_percent": None,
            "reset_at": None,
            "reason": "not exposed",
        }
        self.document["fallback"]["chain"][0]["fallback_route_ids"] = [
            "gemini-secondary"
        ]
        self.assertEqual(
            eligible_route_ids(self.document),
            ("gemini-primary", "claude-gpt-primary", "gemini-secondary"),
        )
        self.assertEqual(
            eligible_route_ids(
                self.document,
                phase="reactive",
                current_route_id="gemini-primary",
            ),
            (),
        )
        self.assertEqual(
            eligible_route_ids(
                self.document,
                phase="reactive",
                current_route_id="gemini-primary",
                signal="quota_exhausted",
            ),
            ("gemini-secondary",),
        )

    def test_fallback_target_has_distinct_account_quota(self):
        source = next(route for route in self.document["routes"] if route["id"] == "gemini-primary")
        target = next(route for route in self.document["routes"] if route["id"] == "gemini-secondary")
        self.assertNotEqual(source["account_id"], target["account_id"])
        self.groups("google-pro-1")["gemini_models"]["weekly"]["remaining_percent"] = 0
        self.assertEqual(
            eligible_route_ids(
                self.document,
                phase="reactive",
                current_route_id="gemini-primary",
                signal="quota_exhausted",
            ),
            (),
        )

    def test_account_observations_match_allowlist(self):
        del self.document["accounts"]["google-pro-2"]
        with self.assertRaises(ContractError):
            validate_document(self.document)

    def test_reactive_signal_must_be_quota_or_rate_limit(self):
        self.document["fallback"]["chain"][0]["fallback_route_ids"] = [
            "claude-gpt-primary"
        ]
        self.assertEqual(
            eligible_route_ids(
                self.document,
                phase="reactive",
                current_route_id="gemini-primary",
                signal="timeout",
            ),
            (),
        )

    def test_no_retry_after_output_or_tool_side_effect(self):
        self.document["fallback"]["chain"][0]["fallback_route_ids"] = [
            "claude-gpt-primary"
        ]
        for kwargs in (
            {"upstream_output_started": True},
            {"tool_side_effect": True},
        ):
            self.assertEqual(
                eligible_route_ids(
                    self.document,
                    phase="reactive",
                    current_route_id="gemini-primary",
                    signal="rate_limited",
                    **kwargs,
                ),
                (),
            )

    def test_manual_only_disables_automatic_candidates(self):
        self.document["manual_only"] = True
        self.assertEqual(eligible_route_ids(self.document), ())

    def test_routes_must_be_allowlisted_and_chain_bounded(self):
        invalid = deepcopy(self.document)
        invalid["routes"][0]["model_id"] = "not-allowlisted"
        with self.assertRaises(ContractError):
            validate_document(invalid)
        invalid = deepcopy(self.document)
        invalid["fallback"]["max_attempts"] = 1
        invalid["fallback"]["chain"][0]["fallback_route_ids"] = [
            "claude-gpt-primary"
        ]
        with self.assertRaises(ContractError):
            validate_document(invalid)

    def test_safety_flags_cannot_be_disabled(self):
        for field in (
            "session_affinity",
            "before_upstream_output_only",
            "respect_provider_limits",
            "no_quota_bypass",
        ):
            invalid = deepcopy(self.document)
            invalid["fallback"][field] = False
            with self.subTest(field=field), self.assertRaises(ContractError):
                validate_document(invalid)

    def test_secret_shaped_fields_are_rejected(self):
        invalid = deepcopy(self.document)
        invalid["extensions"] = {"api_key": "must-not-be-here"}
        with self.assertRaises(ContractError):
            validate_document(invalid)

    def test_cli_returns_expected_exit_codes(self):
        valid = subprocess.run(
            [sys.executable, str(TOOLS / "verify_challenger_fallback_policy.py"), str(EXAMPLE), "--quiet"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(valid.returncode, EXIT_OK, valid.stderr)
        invalid_path = EXAMPLE.with_name(".fallback-policy-invalid-test.json")
        try:
            invalid_path.write_text("{\"schema_version\": 1}", encoding="utf-8")
            invalid = subprocess.run(
                [sys.executable, str(TOOLS / "verify_challenger_fallback_policy.py"), str(invalid_path)],
                capture_output=True,
                text=True,
                check=False,
            )
        finally:
            invalid_path.unlink(missing_ok=True)
        self.assertEqual(invalid.returncode, EXIT_CONTRACT)
        self.assertIn("CONTRACT ERROR", invalid.stderr)


if __name__ == "__main__":
    unittest.main()
