#!/usr/bin/env python3
"""Report fixed Xcode error categories, never raw signing log excerpts."""
import argparse
from collections import Counter
from pathlib import Path
import re

CATEGORIES = (
    ("provisioning", re.compile(r"profil(e|ing)|provision", re.IGNORECASE)),
    ("signing-certificate", re.compile(r"certificate|codesign|signing identity", re.IGNORECASE)),
    ("appstore-auth", re.compile(r"authenticat|API key|credential|not authorized|account|permission|forbidden", re.IGNORECASE)),
    ("app-identity", re.compile(r"bundle identifier|bundle ID|entitlement|app ID", re.IGNORECASE)),
    ("compiler-or-build", re.compile(r"error:|Error Domain=|ARCHIVE FAILED|EXPORT FAILED", re.IGNORECASE)),
)


def summarize(log):
    # Output is composed exclusively of fixed vocabulary and integer counts.
    # Never interpolate a log line: partial/escaped key fragments cannot leak.
    hits = Counter()
    for line in log.splitlines():
        for label, pattern in CATEGORIES:
            if pattern.search(line):
                hits[label] += 1
                break
    if not hits:
        return "Xcode failed; no classified error (raw log retained only on ephemeral runner)."
    return "Xcode failure categories: " + ", ".join(
        f"{label}={hits[label]}" for label, _ in CATEGORIES if hits[label]
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.log.read_text(encoding="utf-8", errors="replace"))
    args.output.write_text(report + "\n", encoding="utf-8")
    print(report)


if __name__ == "__main__":
    main()
