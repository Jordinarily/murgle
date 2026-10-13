#!/usr/bin/env python3
"""Build a runtime-only Murgle ZIP using the Python standard library."""

import argparse
from pathlib import Path, PurePosixPath
import re
import zipfile


def build(root, destination):
    root = Path(root).resolve()
    destination = Path(destination)
    manifest = root / "Murgle.toc"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("Missing or linked Murgle.toc")
    paths = {"Murgle.toc", "Media/MurgleIcon.tga", "LICENSE"}
    for line in manifest.read_text(encoding="utf-8-sig").splitlines():
        entry = line.strip().replace("\\", "/")
        if not entry or entry.startswith("#"):
            continue
        # Only root Lua files and direct Modules children are supported.
        # Expanding the manifest format requires an explicit packaging change.
        if not re.fullmatch(r"(?:Modules/)?[A-Za-z0-9_-]+\.lua", entry):
            raise ValueError(f"Unsupported manifest entry: {entry}")
        paths.add(entry)
    contents = []
    for entry in sorted(paths):
        path = root / entry
        if any((root / part).is_symlink() for part in [entry, *PurePosixPath(entry).parents]):
            raise ValueError(f"Linked package input: {entry}")
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"Missing or empty package input: {entry}")
        contents.append((entry, path.read_bytes()))
    # Validate and read every input before creating a new output; never overwrite.
    with destination.open("xb") as output:
        try:
            with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                for entry, data in contents:
                    info = zipfile.ZipInfo("Murgle/" + entry, (1980, 1, 1, 0, 0, 0))
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    archive.writestr(info, data)
        except Exception:
            destination.unlink()
            raise
    return len(contents)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new ZIP path; parent directory must exist")
    args = parser.parse_args()
    try:
        count = build(Path(__file__).resolve().parents[1], args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Package failed: {error}\n")
    print(f"Packaged {count} files: {args.output}")


if __name__ == "__main__":
    main()
