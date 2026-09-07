#!/usr/bin/env python3
"""Package the complete Windows wallet runtime, including privacy tools."""

import argparse
import datetime
from pathlib import Path
import shutil
import zipfile


def package_portable(source: Path, output: Path, epoch: int) -> None:
    source = source.resolve()
    output = output.resolve()
    if not (source / "Stashi Wallet.exe").is_file():
        raise ValueError("Wallet executable missing")
    if output.is_relative_to(source):
        raise ValueError("Archive output must be outside the runtime directory")
    timestamp = datetime.datetime.fromtimestamp(max(epoch, 315532800), datetime.timezone.utc)
    zip_time = timestamp.timetuple()[:6]
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source)
            if path.suffix.lower() in {".pdb", ".lib", ".exp"}:
                continue
            if not path.is_file():
                continue
            info = zipfile.ZipInfo(relative.as_posix(), date_time=zip_time)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            with path.open("rb") as file, archive.open(info, "w") as entry:
                shutil.copyfileobj(file, entry, 1024 * 1024)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("epoch", type=int)
    args = parser.parse_args()
    package_portable(args.source, args.output, args.epoch)
