import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MENU = ROOT / "tools" / "router_project_menu.ps1"
STARTER = ROOT / "tools" / "start_dashboard.ps1"


def section(source: str, start: str, end: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index + len(start))
    return source[start_index:end_index]


class RouterStartupOptimizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = MENU.read_text(encoding="utf-8-sig")
        cls.starter = STARTER.read_text(encoding="utf-8-sig")
        cls.warmup = section(cls.source, "function Start-RouterWarmup", "function ConvertTo-CcrProvider")
        cls.start_profile = section(cls.source, "function Start-Profile", "function Show-RouterStatus")
        cls.menu = section(cls.source, "function Invoke-Menu", "function Invoke-SelfTest")

    def test_dashboard_entry_detaches_normal_startup_and_keeps_failure_feedback(self):
        entry = (ROOT / "DASHBOARD.bat").read_text(encoding="utf-8-sig")
        for marker in ('start ""', "-WindowStyle Hidden", "-Detached", "startup-error.log"):
            with self.subTest(marker=marker):
                self.assertIn(marker, entry + self.starter)
        self.assertNotIn('"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File', entry)
        self.assertIn("startup-error.log", self.starter)

    def test_launcher_remains_powershell_5_1_compatible(self):
        self.assertTrue(self.source.startswith("#requires -Version 5.1"))
        for unsupported in ("ForEach-Object -Parallel", "Start-ThreadJob", "async", "await"):
            self.assertNotIn(unsupported, self.warmup)

    def test_menu_starts_non_blocking_project_local_warmup_after_routes_render(self):
        route_render = self.menu.index('Get-ModelRoute -Profile $Profiles[$Index] -Tier "default"')
        warmup_call = self.menu.index("Start-RouterWarmup")
        input_prompt = self.menu.index('(Read-Host "Select a profile or action")')
        self.assertLess(route_render, warmup_call)
        self.assertLess(warmup_call, input_prompt)
        self.assertIn('if ($Profiles.Count -gt 0)', self.menu)
        self.assertIn("[System.Diagnostics.Process]::Start($StartInfo)", self.warmup)

    def test_warmup_relaunches_this_script_with_project_local_root(self):
        for marker in (
            "$StartInfo.FileName = $PowerShellPath",
            '$StartInfo.Arguments = \'-NoLogo -NoProfile -ExecutionPolicy Bypass -File {0} -Root {1} -WarmRouter\'',
            '$StartInfo.WorkingDirectory = $RootPath',
            '$StartInfo.UseShellExecute = $false',
            '$StartInfo.CreateNoWindow = $true',
        ):
            self.assertIn(marker, self.warmup)
        self.assertIn('$PSVersionTable.PSEdition -eq "Core"', self.warmup)
        self.assertIn('Join-Path $PSHOME "pwsh.exe"', self.warmup)
        self.assertIn('Join-Path $PSHOME "powershell.exe"', self.warmup)

    def test_warmup_path_does_not_read_credentials_or_launch_provider(self):
        forbidden = (
            "Read-ProtectedSecret",
            "Read-LocalSetting",
            "setting.json",
            "Invoke-Menu",
            "SignInAndImportCodexAccount",
            "Invoke-RouterRpc",
            "Codex",
            "CODEX_HOME",
            ".codex",
        )
        for marker in forbidden:
            with self.subTest(marker=marker):
                self.assertNotIn(marker.casefold(), self.warmup.casefold())

        dispatch = self.source[self.source.index("try {\n    Ensure-StateDirectories") :]
        warmup_dispatch = section(dispatch, "if ($WarmRouter)", "if ($SelfTest)")
        self.assertIn("Ensure-Router", warmup_dispatch)
        self.assertNotIn("Read-ProtectedSecret", warmup_dispatch)
        self.assertNotIn("Read-LocalSetting", warmup_dispatch)

    def test_warmup_uses_verified_router_path_and_start_profile_is_fail_closed(self):
        ensure_router = section(self.source, "function Ensure-Router", "function Start-RouterWarmup")
        verified = section(self.source, "function Assert-VerifiedRouterService", "function Test-GatewayConfigAcceptanceTimeout")
        for marker in (
            "Assert-VerifiedManagementService",
            '"$GatewayUrl/health"',
            "StatusCode -ne 200",
        ):
            self.assertIn(marker, verified)
        self.assertIn("Assert-VerifiedRouterService", ensure_router)
        self.assertIn("Ensure-Router", self.start_profile)
        self.assertLess(self.start_profile.index("Ensure-Router"), self.start_profile.index("Read-ProtectedSecret"))

    def test_warmup_failure_has_a_non_fatal_fallback_without_weakening_verification(self):
        self.assertRegex(self.warmup, re.compile(r"catch\s*\{.*?WarmupProcess\s*=\s*\$null", re.S))
        self.assertIn("route selection will verify startup synchronously", self.warmup)
        self.assertIn("Ensure-Router", self.start_profile)
        self.assertIn("fail-closed authority", self.warmup)

    def test_no_codex_app_or_global_switching_surface_was_added(self):
        self.assertNotIn("Get-Command codex", self.warmup.casefold())
        self.assertNotIn("USERPROFILE", self.warmup.upper())
        self.assertNotIn("WindowsApps", self.warmup)
        self.assertNotIn("Connect agent", self.warmup)

    def test_dashboard_starts_the_same_verified_warmup_in_background(self):
        for marker in (
            "router_project_menu.ps1",
            "-WarmRouter",
            "-WindowStyle Hidden",
            "warmup-started.json",
        ):
            self.assertIn(marker, self.starter)
        self.assertNotIn("Read-ProtectedSecret", self.starter)
        self.assertNotIn("setting.json", self.starter)


if __name__ == "__main__":
    unittest.main()
