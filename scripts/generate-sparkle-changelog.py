#!/usr/bin/env python3

import argparse
import html
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


APPLICATION_NAME = "Simple Podcast Manager"
OLDEST_RELEASE_NOTES_BUILD = 32
TITLE_PATTERN = re.compile(r"^# Simple Podcast Manager (v\S+)$")
INLINE_CODE_PATTERN = re.compile(r"`([^`]+)`")


@dataclass(frozen=True)
class Release:
    build_version: int
    release_tag: str
    notes: tuple[str, ...]


def parse_arguments() -> argparse.Namespace:
    script_path = Path(__file__).resolve()
    repository = script_path.parent.parent

    parser = argparse.ArgumentParser(
        description="Generate version-aware HTML release notes for Sparkle."
    )
    parser.add_argument("--repository", type=Path, default=repository)
    parser.add_argument("--current-notes", type=Path)
    parser.add_argument("--current-info", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail instead of writing when the generated changelog differs from --output.",
    )
    return parser.parse_args()


def run_git(repository: Path, *arguments: str) -> bytes:
    process = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        check=False,
        capture_output=True,
    )
    if process.returncode != 0:
        message = process.stderr.decode("utf-8", errors="replace").strip()
        raise ValueError(f"git {' '.join(arguments)} failed: {message}")
    return process.stdout


def parse_release(notes_data: bytes, info_data: bytes, source: str) -> Release:
    try:
        notes_text = notes_data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError(f"{source} release notes are not UTF-8: {error}") from error

    nonempty_lines = [line.strip() for line in notes_text.splitlines() if line.strip()]
    if not nonempty_lines:
        raise ValueError(f"{source} release notes are empty")

    title_match = TITLE_PATTERN.fullmatch(nonempty_lines[0])
    if title_match is None:
        raise ValueError(
            f"{source} release notes must start with '# {APPLICATION_NAME} v<version>'"
        )

    note_lines = nonempty_lines[1:]
    if not note_lines or any(not line.startswith("- ") for line in note_lines):
        raise ValueError(f"{source} release notes must contain only Markdown bullets")

    try:
        info = plistlib.loads(info_data)
        build_version = int(info["CFBundleVersion"])
        release_tag = str(info["SPMReleaseTag"])
    except (KeyError, TypeError, ValueError, plistlib.InvalidFileException) as error:
        raise ValueError(f"{source} has invalid release metadata: {error}") from error

    title_tag = title_match.group(1)
    if title_tag != release_tag:
        raise ValueError(
            f"{source} release-note tag {title_tag} does not match SPMReleaseTag {release_tag}"
        )

    return Release(
        build_version=build_version,
        release_tag=release_tag,
        notes=tuple(line[2:].strip() for line in note_lines),
    )


def load_releases(
    repository: Path,
    current_notes_path: Path,
    current_info_path: Path,
) -> list[Release]:
    current_release = parse_release(
        current_notes_path.read_bytes(),
        current_info_path.read_bytes(),
        "Current",
    )

    releases_by_build = {current_release.build_version: current_release}
    history = run_git(repository, "log", "--format=%H", "--", "RELEASE_NOTES.md")
    commits = history.decode("ascii").splitlines()

    for commit in commits:
        notes_data = run_git(repository, "show", f"{commit}:RELEASE_NOTES.md")
        info_data = run_git(repository, "show", f"{commit}:Packaging/Info.plist")
        release = parse_release(notes_data, info_data, f"Commit {commit[:8]}")
        releases_by_build.setdefault(release.build_version, release)

    if OLDEST_RELEASE_NOTES_BUILD not in releases_by_build:
        raise ValueError(
            "Release-note history is incomplete: "
            f"build {OLDEST_RELEASE_NOTES_BUILD} was not found. "
            "Generate from a complete git checkout."
        )

    releases = sorted(
        releases_by_build.values(),
        key=lambda release: release.build_version,
        reverse=True,
    )
    if releases[0] != current_release:
        raise ValueError(
            f"Current build {current_release.build_version} is not newer than release-note history"
        )

    return remove_repeated_notes(releases)


def remove_repeated_notes(releases: list[Release]) -> list[Release]:
    seen_notes: set[str] = set()
    deduplicated_oldest_first: list[Release] = []

    for release in reversed(releases):
        unique_notes = tuple(note for note in release.notes if note not in seen_notes)
        if not unique_notes:
            raise ValueError(
                f"Release {release.release_tag} has no notes that are not already present in an older release"
            )
        seen_notes.update(release.notes)
        deduplicated_oldest_first.append(
            Release(
                build_version=release.build_version,
                release_tag=release.release_tag,
                notes=unique_notes,
            )
        )

    return list(reversed(deduplicated_oldest_first))


def render_inline_markdown(text: str) -> str:
    rendered_parts: list[str] = []
    previous_end = 0
    for match in INLINE_CODE_PATTERN.finditer(text):
        rendered_parts.append(html.escape(text[previous_end : match.start()]))
        rendered_parts.append(f"<code>{html.escape(match.group(1))}</code>")
        previous_end = match.end()
    rendered_parts.append(html.escape(text[previous_end:]))
    return "".join(rendered_parts)


def render_changelog(releases: list[Release]) -> str:
    release_sections: list[str] = []
    for release in releases:
        rendered_notes = "\n".join(
            f"                <li>{render_inline_markdown(note)}</li>"
            for note in release.notes
        )
        release_sections.append(
            "\n".join(
                [
                    (
                        f'        <section class="release" data-sparkle-version="{release.build_version}" '
                        f'data-release-tag="{html.escape(release.release_tag)}">'
                    ),
                    f"            <h2>{html.escape(release.release_tag)}</h2>",
                    "            <ul>",
                    rendered_notes,
                    "            </ul>",
                    "        </section>",
                ]
            )
        )

    sections = "\n\n".join(release_sections)
    return f"""<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{APPLICATION_NAME} version history</title>
    <style>
        :root {{
            color-scheme: light dark;
        }}

        body {{
            margin: 0;
            padding: 0 4px 20px;
            color: CanvasText;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
            font-size: 13px;
            line-height: 1.45;
        }}

        h1 {{
            margin: 0 0 14px;
            font-size: 18px;
            line-height: 1.25;
        }}

        .release {{
            padding: 14px 0;
            border-top: 1px solid rgba(128, 128, 128, 0.35);
        }}

        .release h2 {{
            margin: 0 0 8px;
            font-size: 15px;
            line-height: 1.3;
        }}

        .release ul {{
            margin: 0;
            padding-left: 22px;
        }}

        .release li + li {{
            margin-top: 6px;
        }}

        .release code {{
            font-family: ui-monospace, "SFMono-Regular", Menlo, monospace;
            font-size: 0.92em;
        }}

        .release.sparkle-installed-version {{
            opacity: 0.58;
        }}

        .release.sparkle-installed-version::before {{
            content: "Currently installed";
            display: block;
            margin-bottom: 4px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
        }}

        .release.sparkle-installed-version ~ .release {{
            display: none;
        }}
    </style>
</head>
<body>
    <main>
        <h1>What’s new</h1>
{sections}
    </main>
</body>
</html>
"""


def main() -> int:
    arguments = parse_arguments()
    repository = arguments.repository.resolve()
    current_notes = (arguments.current_notes or repository / "RELEASE_NOTES.md").resolve()
    current_info = (arguments.current_info or repository / "Packaging/Info.plist").resolve()
    output = (arguments.output or repository / "SPARKLE_CHANGELOG.html").resolve()

    try:
        releases = load_releases(repository, current_notes, current_info)
        rendered_changelog = render_changelog(releases)
    except (OSError, ValueError) as error:
        print(f"Unable to generate Sparkle changelog: {error}", file=sys.stderr)
        return 1

    if arguments.check:
        try:
            existing_changelog = output.read_text(encoding="utf-8")
        except OSError as error:
            print(f"Unable to read Sparkle changelog {output}: {error}", file=sys.stderr)
            return 1

        if existing_changelog != rendered_changelog:
            print(
                f"Sparkle changelog is stale: {output}\n"
                "Run ./scripts/generate-sparkle-changelog.py and commit the result.",
                file=sys.stderr,
            )
            return 1
        return 0

    try:
        output.write_text(rendered_changelog, encoding="utf-8")
    except OSError as error:
        print(f"Unable to write Sparkle changelog {output}: {error}", file=sys.stderr)
        return 1

    print(f"Generated {output} with {len(releases)} releases.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
