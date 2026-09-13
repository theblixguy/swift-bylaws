import subprocess
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).parents[2] / "Scripts" / "update_zed_registry.py"

_VALID_EXTENSION = """\
id = "bylaws-lsp"
version = "0.10.0"

[language_servers.bylaws]
name = "Bylaws"
"""

_VALID_REGISTRY = """\
[another-extension]
version = "9.0.0"

[bylaws-lsp]
submodule = "extensions/bylaws-lsp"
version = "0.9.0"
path = "Editors/Zed"

[later-extension]
version = "4.0.0"
"""


class UpdateZedRegistryTests(unittest.TestCase):
    def _run_script(
        self,
        extension_text: str,
        registry_text: str,
    ) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            extension_path = root / "extension.toml"
            registry_path = root / "extensions.toml"
            extension_path.write_text(extension_text, encoding="utf-8")
            registry_path.write_text(registry_text, encoding="utf-8")
            result = subprocess.run(
                [
                    str(_SCRIPT),
                    str(extension_path),
                    str(registry_path),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            return result, registry_path.read_text(encoding="utf-8")

    def test_updates_only_the_registry_version(self) -> None:
        result, registry_text = self._run_script(
            _VALID_EXTENSION,
            _VALID_REGISTRY,
        )

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "0.10.0\n")
        self.assertEqual(result.stderr, "")
        self.assertEqual(
            registry_text,
            _VALID_REGISTRY.replace(
                'version = "0.9.0"',
                'version = "0.10.0"',
            ),
        )

    def test_rejects_invalid_updates_without_changing_the_registry(self) -> None:
        cases = [
            (
                "invalid source version",
                _VALID_EXTENSION.replace("0.10.0", "01.10.0"),
                _VALID_REGISTRY,
                "must be MAJOR.MINOR.PATCH",
            ),
            (
                "unchanged version",
                _VALID_EXTENSION.replace("0.10.0", "0.9.0"),
                _VALID_REGISTRY,
                "must be greater than the registry version",
            ),
            (
                "lower version",
                _VALID_EXTENSION.replace("0.10.0", "0.8.0"),
                _VALID_REGISTRY,
                "must be greater than the registry version",
            ),
            (
                "wrong source path",
                _VALID_EXTENSION,
                _VALID_REGISTRY.replace("Editors/Zed", "extension"),
                "source path must be Editors/Zed",
            ),
            (
                "wrong submodule path",
                _VALID_EXTENSION,
                _VALID_REGISTRY.replace(
                    "extensions/bylaws-lsp",
                    "extensions/bylaws",
                ),
                "submodule must be extensions/bylaws-lsp",
            ),
            (
                "invalid registry version",
                _VALID_EXTENSION,
                _VALID_REGISTRY.replace("0.9.0", "0.9"),
                "bylaws-lsp version in the Zed registry must be MAJOR.MINOR.PATCH",
            ),
            (
                "missing registry entry",
                _VALID_EXTENSION,
                _VALID_REGISTRY.replace("[bylaws-lsp]", "[other-name]"),
                "has no bylaws-lsp entry",
            ),
            (
                "malformed registry",
                _VALID_EXTENSION,
                _VALID_REGISTRY.replace(
                    'version = "0.9.0"',
                    "version =",
                ),
                "does not parse as TOML",
            ),
        ]

        for name, extension_text, original_registry_text, message in cases:
            with self.subTest(name):
                result, resulting_registry_text = self._run_script(
                    extension_text,
                    original_registry_text,
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn(message, result.stderr)
                self.assertEqual(resulting_registry_text, original_registry_text)


if __name__ == "__main__":
    unittest.main()
