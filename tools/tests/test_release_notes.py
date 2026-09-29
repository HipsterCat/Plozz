from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


TOOL = Path(__file__).resolve().parents[1] / "release-notes.py"


class ReleaseNotesToolTests(unittest.TestCase):
    def fixture(self, root: Path, items: list[object]) -> Path:
        path = root / "ReleaseNotes.json"
        path.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "releases": [
                        {
                            "id": "release/001",
                            "version": "2026.8.1",
                            "build": 1,
                            "releasedAt": "2026-08-01",
                            "sections": [
                                {
                                    "category": "New",
                                    "items": items,
                                }
                            ],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path

    def run_tool(
        self, catalog: Path, *arguments: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                "python3",
                str(TOOL),
                "--catalog",
                str(catalog),
                *arguments,
            ],
            text=True,
            capture_output=True,
        )

    def test_render_filters_platform_items_and_keeps_shared_strings(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            catalog = self.fixture(
                Path(temp),
                [
                    "Shared",
                    {"text": "TV only", "platforms": ["tvOS"]},
                    {"text": "Phone only", "platforms": ["iOS"]},
                ],
            )

            tv = self.run_tool(
                catalog,
                "render",
                "--release-id",
                "release/001",
                "--platform",
                "tvOS",
            )
            ios = self.run_tool(
                catalog,
                "render",
                "--release-id",
                "release/001",
                "--platform",
                "iOS",
            )

            self.assertEqual(tv.returncode, 0, tv.stderr)
            self.assertEqual(tv.stdout.strip(), "New\n• Shared\n• TV only")
            self.assertEqual(ios.returncode, 0, ios.stderr)
            self.assertEqual(ios.stdout.strip(), "New\n• Shared\n• Phone only")

    def test_validate_rejects_empty_platforms(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            catalog = self.fixture(
                Path(temp),
                [{"text": "Invalid", "platforms": []}],
            )

            result = self.run_tool(catalog, "validate")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("no platforms", result.stderr)

    def test_validate_rejects_unknown_platform(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            catalog = self.fixture(
                Path(temp),
                [{"text": "Invalid", "platforms": ["visionOS"]}],
            )

            result = self.run_tool(catalog, "validate")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown platform", result.stderr)

    def test_render_warns_when_platform_has_no_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            catalog = self.fixture(
                Path(temp),
                [{"text": "TV only", "platforms": ["tvOS"]}],
            )

            result = self.run_tool(
                catalog,
                "render",
                "--release-id",
                "release/001",
                "--platform",
                "iOS",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "\n")
            self.assertIn("has no iOS notes", result.stderr)

    def revised_catalog(self, root: Path, versions=("2026.9.29.10", "2026.9.29.9")) -> Path:
        path = self.fixture(root, ["Shared"])
        catalog = json.loads(path.read_text())
        catalog["releases"] = [
            {
                "id": f"release/{50 - index:03d}",
                "version": version,
                "marketingVersion": "2026.9.25",
                "build": 50 - index,
                "releasedAt": "2026-09-29",
                "sections": [{"category": "New", "items": ["Shared"]}],
            }
            for index, version in enumerate(versions)
        ] + catalog["releases"]
        path.write_text(json.dumps(catalog))
        return path

    def test_identity_keeps_apple_version_and_local_builds_unreleased(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.revised_catalog(Path(temp))
            before = path.read_bytes()
            for _ in range(2):
                local = self.run_tool(path, "identity")
                self.assertEqual(local.returncode, 0, local.stderr)
                self.assertEqual(json.loads(local.stdout), {
                    "marketingVersion": "2026.9.25", "releaseVersion": "", "releaseID": ""
                })
                selected = self.run_tool(path, "identity", "--release-id", "release/050",
                                         "--version", "2026.9.25", "--build", "50")
                self.assertEqual(selected.returncode, 0, selected.stderr)
                self.assertEqual(json.loads(selected.stdout), {
                    "marketingVersion": "2026.9.25",
                    "releaseVersion": "2026.9.29.10", "releaseID": "release/050"
                })
            self.assertEqual(path.read_bytes(), before)

    def test_legacy_identity_and_explicit_new_apple_series(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.fixture(Path(temp), ["Shared"])
            for arguments, expected in (
                ((), "2026.8.1"), (("--version", "2026.10.1"), "2026.10.1")
            ):
                result = self.run_tool(path, "identity", *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout)["marketingVersion"], expected)
            invalid = self.run_tool(path, "identity", "--version", "2026.9.29.1")
            self.assertNotEqual(invalid.returncode, 0)

    def test_selected_identity_rejects_mismatched_apple_version_build_and_id(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.revised_catalog(Path(temp))
            for arguments in (
                ("--release-id", "release/999"),
                ("--release-id", "release/050", "--build", "51"),
                ("--release-id", "release/050", "--version", "2026.9.29"),
                ("--release-id", "release/050", "--version", "2026.9.29.10"),
            ):
                with self.subTest(arguments=arguments):
                    self.assertNotEqual(self.run_tool(path, "identity", *arguments).returncode, 0)
            valid = self.run_tool(path, "validate", "--release-id", "release/050",
                                  "--version", "2026.9.25", "--build", "50")
            self.assertEqual(valid.returncode, 0, valid.stderr)

    def test_next_revision_is_numeric_non_mutating_and_resets_each_day(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.revised_catalog(Path(temp))
            before = path.read_bytes()
            for day, expected in (("2026-09-29", "2026.9.29.11"),
                                  ("2026-09-30", "2026.9.30.1"),
                                  ("2026-09-29", "2026.9.29.11")):
                result = self.run_tool(path, "next-version", "--date", day)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)
            self.assertNotEqual(
                self.run_tool(path, "next-version", "--date", "2026-09-28").returncode, 0
            )
            self.assertEqual(path.read_bytes(), before)

    def test_new_releases_require_unique_valid_revisions_and_explicit_apple_version(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            for changes in (
                {"version": "2026.9.29.0"}, {"version": "2026.9.29.09"},
                {"version": "2026.9.29.9"}, {"version": "2026.9.29.8"},
                {"version": "2026.9.30.1"}, {"version": "2026.2.31.1"},
                {"marketingVersion": "2026.9.29.1"}, {"marketingVersion": None},
                {"marketingVersion": "2026.9.24"},
            ):
                with self.subTest(changes=changes):
                    path = self.revised_catalog(Path(temp))
                    data = json.loads(path.read_text())
                    data["releases"][0].update(changes)
                    if changes.get("marketingVersion", "") is None:
                        data["releases"][0].pop("marketingVersion")
                    path.write_text(json.dumps(data))
                    self.assertNotEqual(self.run_tool(path, "validate").returncode, 0)

    def test_new_release_notes_identify_display_version_and_explicit_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = self.revised_catalog(Path(temp))
            result = self.run_tool(path, "render", "--release-id", "release/050")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "Plozz 2026.9.29.10\n\nNew\n• Shared")
            data = json.loads(path.read_text())
            data["releases"][0]["sections"][0]["items"] = [
                {"text": "TV only", "platforms": ["tvOS"]}
            ]
            path.write_text(json.dumps(data))
            result = self.run_tool(path, "render", "--release-id", "release/050",
                                   "--platform", "iOS", "--empty-text", "No changes.")
            self.assertEqual(result.stdout.strip(), "Plozz 2026.9.29.10\n\nNo changes.")


if __name__ == "__main__":
    unittest.main()
