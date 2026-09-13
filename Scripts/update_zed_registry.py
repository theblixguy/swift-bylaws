#!/usr/bin/env python3

import re
import sys
import tomllib
from collections.abc import Mapping
from pathlib import Path

_VERSION_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
)
_SECTION_PATTERN = re.compile(r"(?m)^\[bylaws-lsp\][ \t]*(?:#.*)?$")
_NEXT_SECTION_PATTERN = re.compile(r"(?m)^\[")
_VERSION_LINE_PATTERN = re.compile(
    r"(?m)^(?P<prefix>[ \t]*version[ \t]*=[ \t]*)"
    r'(?P<quote>["\'])[^"\']*'
    r"(?P=quote)(?P<suffix>[ \t]*(?:#.*)?)$"
)


class _CommandError(Exception):
    pass


def _read_toml(path: Path) -> tuple[str, dict[str, object]]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        raise _CommandError(f"Cannot read {path}: {error}") from error
    try:
        return text, tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise _CommandError(f"{path} does not parse as TOML: {error}") from error


def _parse_version(
    value: object,
    invalid_message: str,
) -> tuple[int, int, int]:
    if not isinstance(value, str) or _VERSION_PATTERN.fullmatch(value) is None:
        raise _CommandError(invalid_message)
    major, minor, patch = (int(part) for part in value.split("."))
    return major, minor, patch


def _extension_version(path: Path) -> tuple[str, tuple[int, int, int]]:
    _, document = _read_toml(path)
    version = _parse_version(
        document.get("version"),
        f"The version in {path} must be MAJOR.MINOR.PATCH.",
    )
    return ".".join(str(part) for part in version), version


def _registry_entry(path: Path) -> tuple[str, Mapping[str, object]]:
    text, document = _read_toml(path)
    entry = document.get("bylaws-lsp")
    if not isinstance(entry, Mapping):
        raise _CommandError("The Zed registry has no bylaws-lsp entry.")
    return text, entry


def _replace_version(text: str, version: str) -> str:
    sections = list(_SECTION_PATTERN.finditer(text))
    if len(sections) != 1:
        message = (
            "The Zed registry has no bylaws-lsp entry."
            if not sections
            else "The Zed registry has more than one bylaws-lsp entry."
        )
        raise _CommandError(message)

    section_start = sections[0].end()
    next_section = _NEXT_SECTION_PATTERN.search(text, section_start)
    section_end = next_section.start() if next_section else len(text)
    section = text[section_start:section_end]
    versions = list(_VERSION_LINE_PATTERN.finditer(section))
    if len(versions) != 1:
        message = (
            "The bylaws-lsp registry entry has no version string."
            if not versions
            else "The bylaws-lsp registry entry has more than one version string."
        )
        raise _CommandError(message)

    match = versions[0]
    replacement = (
        f"{match.group('prefix')}{match.group('quote')}{version}"
        f"{match.group('quote')}{match.group('suffix')}"
    )
    changed_section = section[: match.start()] + replacement + section[match.end() :]
    return text[:section_start] + changed_section + text[section_end:]


def _update_registry(extension_path: Path, registry_path: Path) -> str:
    requested_text, requested = _extension_version(extension_path)
    registry_text, entry = _registry_entry(registry_path)
    if entry.get("submodule") != "extensions/bylaws-lsp":
        raise _CommandError(
            "The bylaws-lsp registry submodule must be extensions/bylaws-lsp."
        )
    if entry.get("path") != "Editors/Zed":
        raise _CommandError("The bylaws-lsp registry source path must be Editors/Zed.")
    current = _parse_version(
        entry.get("version"),
        "The bylaws-lsp version in the Zed registry must be MAJOR.MINOR.PATCH.",
    )
    if requested <= current:
        raise _CommandError(
            "The Zed version must be greater than the registry version."
        )

    changed_text = _replace_version(registry_text, requested_text)
    temporary_path = registry_path.with_name(registry_path.name + ".tmp")
    try:
        temporary_path.write_text(changed_text, encoding="utf-8")
        temporary_path.replace(registry_path)
    except OSError as error:
        temporary_path.unlink(missing_ok=True)
        raise _CommandError(f"Cannot write {registry_path}: {error}") from error
    return requested_text


def _main(arguments: list[str]) -> int:
    if len(arguments) != 2:
        print(
            f"Usage: {Path(sys.argv[0]).name} EXTENSION_TOML REGISTRY_TOML",
            file=sys.stderr,
        )
        return 2
    try:
        version = _update_registry(Path(arguments[0]), Path(arguments[1]))
    except _CommandError as error:
        print(error, file=sys.stderr)
        return 1
    print(version)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
