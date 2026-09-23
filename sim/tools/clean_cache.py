"""Remove regenerable compiler headers while preserving simulation evidence."""
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=Path("build"))
    args = parser.parse_args()
    count = size = 0
    for path in args.build_dir.rglob("*.gch"):
        if path.is_file() and not path.is_symlink():
            size += path.stat().st_size
            path.unlink()
            count += 1
    print(f"Removed {count} compiler caches; reclaimed {size / 1024**3:.2f} GiB")


if __name__ == "__main__":
    main()
