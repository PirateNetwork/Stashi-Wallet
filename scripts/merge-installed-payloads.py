#!/usr/bin/env python3
"""Merge installed-file digests from release metadata for GPG signing."""

import pathlib
import re
import sys
import zipfile


LINE = re.compile(r"^([0-9a-fA-F]{64})[ \t]+[*]?([^\\/]+)$")
SOURCE = re.compile(r"^installed-payload-([a-z0-9]+(?:-[a-z0-9]+)*)\.txt$")


def merge(archive_path: pathlib.Path, output_path: pathlib.Path) -> None:
    entries: dict[str, str] = {}
    with zipfile.ZipFile(archive_path) as archive:
        by_platform: dict[str, list[str]] = {}
        for name in sorted(archive.namelist()):
            filename = pathlib.PurePosixPath(name).name
            match = SOURCE.fullmatch(filename)
            if match is None:
                continue
            platform = match.group(1).removesuffix("-unsigned")
            by_platform.setdefault(platform, []).append(name)

        for platform, names in sorted(by_platform.items()):
            signed_name = f"installed-payload-{platform}.txt"
            source = next(
                (name for name in names if pathlib.PurePosixPath(name).name == signed_name),
                names[0],
            )
            for raw_line in archive.read(source).decode("utf-8").splitlines():
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                match = LINE.fullmatch(line)
                if match is None:
                    raise ValueError(f"Invalid installed payload checksum in {source}: {raw_line!r}")
                digest, filename = match.groups()
                # The ARM64 and x64 Linux executables have the same on-disk
                # basename. Qualify the signed record, not the installed file.
                if platform == "linux-arm64":
                    filename = f"{filename}-linux-arm64"
                digest = digest.lower()
                previous = entries.setdefault(filename, digest)
                if previous != digest:
                    raise ValueError(f"Conflicting installed payload checksum for {filename}")

    if entries:
        output_path.write_text(
            "".join(f"{digest}  {filename}\n" for filename, digest in sorted(entries.items())),
            encoding="utf-8",
            newline="\n",
        )


if __name__ == "__main__":
    try:
        merge(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
    except (IndexError, OSError, ValueError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from error
