"""Check the public diary against the build advertised in the repository."""

import argparse
import plistlib
import posixpath
import re
from pathlib import Path


STEP_HEADING = re.compile(r"^## \d{4}-\d{2}-\d{2} — Step (\d+) — ", re.M)
SECTION_HEADING = re.compile(r'^((?:<a id="dev-step-\d+"></a>\n\n)?)(?:#|##) .+', re.M)
LINK_TARGET = re.compile(r"\]\(([^)\s]+)\)")
RECENT_COUNT = 10
ARCHIVE_PAGE_BYTES = 128 * 1024
SOURCE_DIRECTORY = "PhotoCraftSwift/docs"
RAW_DIARY = (
    "https://raw.githubusercontent.com/ForensicIntelligence/Photato/main/"
    f"{SOURCE_DIRECTORY}/DEVELOPMENT_DIARY.md"
)


def rebase_links(markup: str, directory: str, anchors: dict[str, str] | None = None) -> str:
    def resolve_link(match: re.Match[str]) -> str:
        target = match[1]
        if target.startswith("#"):
            return f"]({anchors[target]}{target})" if anchors and target in anchors else match[0]
        if target.startswith("/") or ":" in target.split("#", 1)[0]:
            return match[0]
        return "](" + posixpath.normpath(f"{directory}/{target}") + ")"

    return LINK_TARGET.sub(resolve_link, markup)


def recent_page(diary: str, build: int) -> str:
    headings = list(STEP_HEADING.finditer(diary))
    if len(headings) <= RECENT_COUNT or [int(heading[1]) for heading in headings[:RECENT_COUNT]] != list(range(build, build - RECENT_COUNT, -1)):
        raise ValueError(f"The source diary must start with the latest {RECENT_COUNT} consecutive entries.")
    entries = diary[headings[0].start():headings[RECENT_COUNT].start()].strip()

    return (
        "# Photato Developer Diary\n\n"
        "**[Full diary archive on GitHub](diary/README.md)** · "
        "[Website edition](https://www.forensicintelligence.ca/photato/diary.html#entries)\n\n"
        f"Source build **{build}** · The {RECENT_COUNT} most recent entries, newest first.\n\n"
        f"{rebase_links(entries, SOURCE_DIRECTORY)}\n"
    )


def archive_pages(diary: str) -> dict[str, str]:
    # Work backwards so new entries at the start do not move the older pages.
    boundaries = [0, *(m.start() for m in SECTION_HEADING.finditer(diary) if m.start()), len(diary)]
    parts: list[list[str]] = [[]]
    size = 0
    for start, end in reversed(list(zip(boundaries, boundaries[1:]))):
        section = diary[start:end]
        length = len(section.encode("utf-8"))
        if length > ARCHIVE_PAGE_BYTES:
            raise ValueError("Split the oversized diary section before publishing the GitHub archive.")
        if size + length > ARCHIVE_PAGE_BYTES:
            parts.append([])
            size = 0
        parts[-1].append(section)
        size += length

    sections = {f"part-{number:02d}.md": "".join(reversed(part)) for number, part in enumerate(parts, 1)}
    anchors = {
        f"#{anchor}": name
        for name, part in sections.items()
        for anchor in re.findall(r'^<a id="(dev-step-\d+)"></a>', part, re.M)
    }
    pages = {}
    reading_order = list(reversed(sections))
    for index, name in enumerate(reading_order):
        navigation = ["[Latest entries](../DEVELOPER_DIARY.md)", "[Archive index](README.md)"]
        if index:
            navigation.append(f"[Previous page]({reading_order[index - 1]})")
        if index + 1 < len(reading_order):
            navigation.append(f"[Next page]({reading_order[index + 1]})")
        links = " · ".join(navigation)
        content = rebase_links(sections[name].strip(), f"../{SOURCE_DIRECTORY}", anchors)
        pages[name] = f"{links}\n\n{content}\n\n{links}\n"

    index_page = next((name for name, part in sections.items() if "## Complete chronological index\n" in part), None)
    if index_page is None:
        raise ValueError("The source diary needs its complete chronological index.")
    pages["README.md"] = (
        "# Photato Developer Diary Archive\n\n"
        "[Latest entries](../DEVELOPER_DIARY.md) · "
        f"[Chronological index]({index_page}#complete-chronological-index)\n\n"
        "The full diary is split into pages for GitHub. Start at the top or use the chronological index to look up a checkpoint.\n\n"
        + "\n".join(f"- [Page {index}]({name})" for index, name in enumerate(reading_order, 1))
        + f"\n\n[Download the full diary as Markdown]({RAW_DIARY}) · "
        f"[Download the detailed development log]({RAW_DIARY.rsplit('/', 1)[0]}/DEVLOG.md)\n"
    )
    return {f"diary/{name}": page for name, page in pages.items()}


def check(*, write: bool = False) -> int:
    root = Path(__file__).resolve().parents[1]
    project = root / "PhotoCraftSwift"
    docs = project / "docs"
    with (project / "scripts/Info.plist").open("rb") as info:
        build = int(plistlib.load(info)["CFBundleVersion"])

    readme = (root / "README.md").read_text(encoding="utf-8")
    top = "\n".join(readme.splitlines()[:10])
    diary_link = "[Developer Diary](DEVELOPER_DIARY.md)"
    if diary_link not in top:
        raise ValueError("Put the Developer Diary link near the top of README.md.")
    if "[Full diary archive](diary/README.md)" not in top:
        raise ValueError("Put the full diary archive link near the top of README.md.")
    if re.findall(r"^\*\*Development alpha — source build (\d+)\.", readme, re.M) != [str(build)]:
        raise ValueError(f"The README must advertise source build {build}.")

    diary = (docs / "DEVELOPMENT_DIARY.md").read_text(encoding="utf-8")
    log = (docs / "DEVLOG.md").read_text(encoding="utf-8")
    anchor = f"dev-step-{build:03d}"
    if re.findall(r"<!-- current-status-step:(\d+) -->", diary) != [str(build)]:
        raise ValueError(f"The diary's current status must identify step {build}.")
    if not re.search(rf"^## \d{{4}}-\d{{2}}-\d{{2}} — Step {build} — ", diary, re.M):
        raise ValueError(f"Add the diary entry for step {build}.")
    if not re.search(rf"^\| [^\n]*\| {build} \| [^\n]*\(DEVLOG\.md#{anchor}\)", diary, re.M):
        raise ValueError(f"Link step {build} from the diary's chronological index.")

    anchors = [int(step) for step in re.findall(r'^<a id="dev-step-(\d+)"></a>', log, re.M)]
    if not anchors or max(anchors) != build or anchors.count(build) != 1:
        raise ValueError(f"The latest detailed development log entry must be step {build}.")
    if not re.search(rf"^\| {build} \| [^\n]*\(#{anchor}\)", log, re.M):
        raise ValueError(f"Link step {build} from the detailed log's chronological index.")
    generated = {"DEVELOPER_DIARY.md": recent_page(diary, build), **archive_pages(diary)}
    for name, content in generated.items():
        page = root / name
        if write:
            page.parent.mkdir(parents=True, exist_ok=True)
            if not page.exists() or page.read_text(encoding="utf-8") != content:
                page.write_text(content, encoding="utf-8")
        elif not page.is_file() or page.read_text(encoding="utf-8") != content:
            raise ValueError(f"Refresh {name} with python3 scripts/check-diary.py --write.")
    for page in (root / "diary").glob("part-*.md"):
        if f"diary/{page.name}" not in generated:
            if not write:
                raise ValueError(f"Remove the obsolete archive page {page.name} with python3 scripts/check-diary.py --write.")
            page.unlink()
    return build


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Refresh the GitHub Developer Diary from the source records.")
    options = parser.parse_args()
    try:
        print(f"GitHub README and diary records match source build {check(write=options.write)}.")
    except (KeyError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
