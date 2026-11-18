"""Check the public diary against the build advertised in the repository."""

import argparse
import plistlib
import posixpath
import re
from pathlib import Path


STEP_HEADING = re.compile(r"^## \d{4}-\d{2}-\d{2} — Step (\d+) — ", re.M)
RECENT_COUNT = 10


def recent_page(diary: str, build: int) -> str:
    headings = list(STEP_HEADING.finditer(diary))
    if len(headings) <= RECENT_COUNT or [int(heading[1]) for heading in headings[:RECENT_COUNT]] != list(range(build, build - RECENT_COUNT, -1)):
        raise ValueError(f"The source diary must start with the latest {RECENT_COUNT} consecutive entries.")
    entries = diary[headings[0].start():headings[RECENT_COUNT].start()].strip()

    def resolve_link(match: re.Match[str]) -> str:
        target = match[1]
        if target.startswith(("#", "/")) or ":" in target.split("#", 1)[0]:
            return match[0]
        return "](" + posixpath.normpath("PhotoCraftSwift/docs/" + target) + ")"

    markup = re.sub(r"\]\(([^)\s]+)\)", resolve_link, entries)
    return (
        "# Photato Developer Diary\n\n"
        "[Complete diary](https://www.forensicintelligence.ca/photato/diary.html#entries) · "
        "[Full diary Markdown](https://raw.githubusercontent.com/ForensicIntelligence/Photato/main/PhotoCraftSwift/docs/DEVELOPMENT_DIARY.md) · "
        "[Detailed development log](PhotoCraftSwift/docs/DEVLOG.md)\n\n"
        f"The {RECENT_COUNT} most recent entries, newest first.\n\n"
        f"{markup}\n"
    )


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
    generated = recent_page(diary, build)
    page = root / "DEVELOPER_DIARY.md"
    if write:
        page.write_text(generated, encoding="utf-8")
    if page.read_text(encoding="utf-8") != generated:
        raise ValueError("Refresh DEVELOPER_DIARY.md with python3 scripts/check-diary.py --write.")
    return build


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Refresh the GitHub Developer Diary from the source records.")
    options = parser.parse_args()
    try:
        print(f"GitHub README and diary records match source build {check(write=options.write)}.")
    except (KeyError, OSError, ValueError) as error:
        raise SystemExit(str(error)) from error
