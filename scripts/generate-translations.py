#!/usr/bin/env python3
"""Generates Source/Resources/<language>.lproj/Localizable.strings.

The keys are the English texts the app shows (LDLocalized(@"...") in
Source/*.m). Their translations come from WinDirStat's language files
(references/WinDirStat/windirstat/res/langs/lang_*.txt; GPL-3.0-or-later
since WinDirStat 2.9.2, GPL-2.0-or-later before):
a key is translated when it is the same text as one of WinDirStat's English
strings, ignoring Windows accelerators (&), "..." against "…", a trailing
colon and letter case, or when MANUAL maps it to a WinDirStat string ID. A
WinDirStat placeholder ({}) takes the key's format specifiers in order.
Keys the pinned WinDirStat no longer has (it renamed or dropped them) are
looked up in FALLBACK_REVISIONS, older WinDirStat commits read from the
submodule's history. Keys without a translation are left out, so the
English text is shown.

Run it again after adding or changing UI text:

    python3 scripts/generate-translations.py [--report]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LANGS = REPO / "references/WinDirStat/windirstat/res/langs"
OUT = REPO / "Source/Resources"
# Older WinDirStat commits whose strings LinDirStat still uses after the pin
# moved past them: 7da9c724 was the pin before 0.1.5 (GPL-2.0-or-later).
FALLBACK_REVISIONS = ["7da9c7247a1df11687da63a08d7a2edbea8b4561"]

# WinDirStat file suffix -> .lproj name (Apple's codes; GNUstep reads the same).
LANGUAGE_DIRS = {
    "cs": "cs", "da": "da", "de": "de", "es": "es", "et": "et", "fi": "fi", "fr": "fr", "hu": "hu", "it": "it",
    "ja": "ja", "ko": "ko", "nb": "nb", "nl": "nl", "pl": "pl", "pt": "pt", "ru": "ru", "sl": "sl", "sv": "sv",
    "tr": "tr", "uk": "uk", "zh": "zh-Hans", "zh-HK": "zh-HK",
}

# Keys whose WinDirStat counterpart is worded differently (same meaning).
MANUAL = {
    # Not mapped: Show in Finder/Files and Open Terminal Here, whose
    # WinDirStat strings name Explorer and the Command Prompt.
    "Open": "IDS_CLEANUP_OPEN_SELECTED",
    "Size proportion of total scan: %.1f%%\nSize proportion of parent folder: %.1f%%": "IDS_SIZE_PROPORTION_TOOLTIPss",
    "Move to Trash": "IDS_MENU_DELETE_BIN",
    "Delete Permanently…": "IDS_MENU_DELETE",
    "Empty Folder…": "IDS_MENU_EMPTY_FOLDER",
    "Empty Trash": "IDS_MENU_EMPTY_BIN",
    "Empty Trash…": "IDS_MENU_EMPTY_BIN",
    "Refresh": "IDS_MENU_REFRESH_ALL",
    "Reset Zoom": "IDS_MENU_ZOOMRESET",
    "Settings…": "IDS_MENU_SETTINGS",
    "Settings": "IDS_MENU_SETTINGS",
    "Preferences": "IDS_MENU_SETTINGS",
    "Report a Bug…": "IDS_MENU_HELP_REPORT",
    "Quit": "IDS_MENU_EXIT",
    "Move To": "IDS_MENU_MOVE_TO",
    "Load Results From CSV/JSON": "IDS_MENU_LOAD_RESULTS",
    "Save Results To CSV/JSON": "IDS_MENU_SAVE_RESULTS",
    "Save Duplicates To CSV/JSON": "IDS_MENU_SAVE_DUPLICATES",
    "Select Target": "IDS_MENU_SELECT",
    "Show Status Bar": "IDS_MENU_STATUS_BAR",
    "Suspend Scan": "IDS_SUSPEND",
    "Resume Scan": "IDS_RESUME",
    "Scan for duplicate files (slower)": "IDS_DUPLICATES_SCAN",
    "Scan for duplicate files": "IDS_DUPLICATES_SCAN",
    "Scan and display hard link information": "IDS_PAGE_ADVANCED_PROCESS_HARDLINKS",
    "Folder history entries": "IDS_PAGE_ADVANCED_FOLDER_HISTORY",
    "Largest files shown": "IDS_PAGE_ADVANCED_LARGEST_COUNT",
    "Scanning threads": "IDS_PAGE_ADVANCED_THREADS",
    "Exclude files smaller than": "IDS_PAGE_FILTERING_SIZE_MIN",
    "Use regular expressions instead of glob patterns": "IDS_PAGE_FILTERING_USE_REGEX",
    "Invalid filter: %@": "IDS_PAGE_FILTERING_INVALID_FILTER",
    "Recurse into subfolders": "IDS_PAGE_CLEANUPS_RECURSE",
    "Move Up": "IDS_PAGE_CLEANUPS_UP",
    "Move Down": "IDS_PAGE_CLEANUPS_DOWN",
    "Title": "IDS_PAGE_CLEANUPS_NAME",
    "Highlight color": "IDS_PAGE_TREEMAP_BORDER_COLOR",
    "Light Source": "IDS_PAGE_TREEMAP_INCIDENCE",
    "Show sizes in human-readable format": "IDS_PAGE_GENERAL_SHOW_SIZES",
    "Warn before deleting": "IDS_PAGE_PROMPTS_DELETION_WARNING",
    "Level colors": "IDS_PAGE_TREELIST_COLORS",
    "Case sensitive": "IDS_SEARCH_CASE",
    "Match the whole name": "IDS_SEARCH_WHOLE_PHRASE",
    "Use regular expressions (POSIX extended)": "IDS_SEARCH_REGEX",
    "Find files whose name contains:": "IDS_SEARCH_LABEL",
    "Memory: %@": "IDS_RAMUSAGEs",
    "Scan suspended": "IDS_SUSPENDED",
    "Files without an extension": "IDS_EXTENSION_MISSING",
    "Language": "IDS_PAGE_GENERAL_LANGUAGE",
    "SequoiaView Layout": "IDS_PAGE_TREEMAP_SEQUOIA",
}

# Keys that are one item of a comma-separated WinDirStat string.
LIST_ITEMS = {
    "Created": ("IDS_WATCHER_VERBS", 0), "Deleted": ("IDS_WATCHER_VERBS", 1),
    "Modified": ("IDS_WATCHER_VERBS", 2), "Renamed (Old)": ("IDS_WATCHER_VERBS", 3),
    "Renamed (New)": ("IDS_WATCHER_VERBS", 4),
}

LITERAL = re.compile(r'LDLocalized\(\s*((?:@"(?:[^"\\]|\\.)*"\s*)+)\)')
PIECE = re.compile(r'@"((?:[^"\\]|\\.)*)"')
SPEC = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?[@diouxXfFeEgGcCsSpaA%]")


def objc_unescape(text):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(m.group(1), m.group(1)), text)


def strings_escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def collect_keys():
    keys = set()
    for path in sorted((REPO / "Source").glob("*.m")):
        for match in LITERAL.finditer(path.read_text()):
            keys.add(objc_unescape("".join(PIECE.findall(match.group(1)))))
    return keys


def load_language(path):
    return parse_language(path.read_text(encoding="utf-8-sig"))


def load_language_at(revision, name):
    """A language file as it was in an older WinDirStat commit, or {}."""
    result = subprocess.run(["git", "-C", str(REPO / "references/WinDirStat"), "show",
                             f"{revision}:windirstat/res/langs/{name}"], capture_output=True)
    if result.returncode != 0:
        return {}
    return parse_language(result.stdout.decode("utf-8-sig"))


def parse_language(text):
    strings = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith(("#", ";")):
            key, value = line.split("=", 1)
            strings[key.strip()] = value.replace("\\n", "\n").replace("\\t", "\t")
    return strings


def plain(text):
    """Comparable form: no accelerators, one ellipsis style, no trailing colon.
    WinDirStat's "Tooltip.\nLabel" commands compare by their label."""
    if "\n" in text and not text.startswith("\n"):
        text = text.rsplit("\n", 1)[1]
    text = text.replace("WinDirStat", "LinDirStat")
    # Windows mnemonics: "&File", and "設定(&S)" in CJK languages.
    text = re.sub(r"\s*\(&[A-Za-z0-9]\)", "", text)
    text = text.replace("&&", "\0").replace("&", "").replace("\0", "&")
    text = text.replace("...", "…").strip()
    return text[:-1].strip() if text.endswith(":") else text


def normalized(text):
    return SPEC.sub("{}", plain(text)).lower()


def translate(key, wds_english, wds_text):
    """WinDirStat's translation shaped like key, or None when they do not fit."""
    # A key of several lines keeps them all (plain keeps a tooltip's label).
    value = wds_text.strip() if "\n" in key else plain(wds_text)
    specs = [s for s in SPEC.findall(key) if s != "%%"]
    holes = value.count("{}")
    if holes == 0 and len(specs) == 1 and key.endswith(": " + specs[0]):
        value = value.rstrip(":").rstrip() + ": {}"
        holes = 1
    if holes != len(specs) or SPEC.search(value):
        return None
    # A literal percent sign, as in "{}%", is "%%" in a format key.
    if "%%" in key:
        value = value.replace("%", "%%")
    for spec in specs:
        value = value.replace("{}", spec, 1)
    if key.endswith("…") and not value.endswith("…"):
        value += "…"
    if value.endswith("…") and not key.endswith("…"):
        value = value[:-1].rstrip()
    value = value.strip()
    if key.rstrip().endswith(":") and not value.endswith(":"):
        value += ":"
    if key.endswith(" ") and not value.endswith(" "):
        value += " "
    return value


def main():
    if not LANGS.is_dir():
        print("missing WinDirStat language files: git submodule update --init references/WinDirStat", file=sys.stderr)
        return 2
    keys = collect_keys()
    english = load_language(LANGS / "lang_en.txt")
    by_text = {}
    for string_id, text in english.items():
        by_text.setdefault(normalized(text), string_id)
    ids = {}
    for key in keys:
        string_id = MANUAL.get(key)
        if string_id not in english:
            string_id = by_text.get(normalized(key))
        if string_id and string_id in english:
            ids[key] = string_id
    # Keys the pin lacks, resolved against the older commits: (revision, id).
    fallback = {}
    for revision in FALLBACK_REVISIONS:
        old_english = load_language_at(revision, "lang_en.txt")
        old_by_text = {}
        for string_id, text in old_english.items():
            old_by_text.setdefault(normalized(text), string_id)
        for key in keys - set(ids) - set(fallback):
            string_id = MANUAL.get(key) or old_by_text.get(normalized(key))
            if string_id and string_id in old_english:
                fallback[key] = (revision, string_id, old_english[string_id])
    report = "--report" in sys.argv
    if report:
        covered = set(ids) | set(fallback) | (set(LIST_ITEMS) & keys)
        print(f"{len(covered)} of {len(keys)} keys have a WinDirStat counterpart")
        for key in sorted(keys - covered):
            print("  untranslated:", key.replace("\n", "\\n"))
    for suffix, directory in LANGUAGE_DIRS.items():
        source = LANGS / f"lang_{suffix}.txt"
        if not source.exists():
            continue
        strings = load_language(source)
        old_strings = {revision: load_language_at(revision, f"lang_{suffix}.txt") for revision in FALLBACK_REVISIONS}
        lines = [f"/* Generated by scripts/generate-translations.py from WinDirStat's lang_{suffix}.txt",
                 "   (GPL-3.0-or-later; strings it dropped from older, GPL-2.0-or-later commits).",
                 "   Do not edit; run the script again. */", ""]
        count = 0
        for key in sorted(set(ids) | set(fallback) | set(LIST_ITEMS)):
            if key in LIST_ITEMS and key in keys:
                string_id, index = LIST_ITEMS[key]
                items = strings.get(string_id, "").split(",")
                value = items[index].strip() if len(items) == len(english[string_id].split(",")) else None
            elif key in ids:
                text = strings.get(ids[key])
                value = translate(key, english[ids[key]], text) if text else None
            elif key in fallback:
                revision, string_id, old_english = fallback[key]
                text = old_strings[revision].get(string_id)
                value = translate(key, old_english, text) if text else None
            else:
                continue
            if value is None or value == key:
                continue
            lines.append(f'"{strings_escape(key)}" = "{strings_escape(value)}";')
            count += 1
        target = OUT / f"{directory}.lproj"
        target.mkdir(parents=True, exist_ok=True)
        (target / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        if report:
            print(f"{directory}: {count} strings")
    # English needs no table, but its folder makes English a listed localization.
    (OUT / "en.lproj").mkdir(parents=True, exist_ok=True)
    (OUT / "en.lproj/Localizable.strings").write_text(
        "/* English is the development language: the keys are the English text. */\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
