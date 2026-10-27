#!/usr/bin/env python3
"""Read FRAME157 eMMC twice per chunk while Android is stopped in loader mode."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "build/src/rkdeveloptool/rkdeveloptool"
SECTORS = 61079552  # rfi and Android block size agree on this FRAME157.
CHUNK_SECTORS = 524288


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as src:
        for data in iter(lambda: src.read(4 * 1024 * 1024), b""):
            h.update(data)
    return h.hexdigest()


def read_chunk(start, count, path, log):
    with log.open("wb") as output:
        subprocess.run([str(TOOL), "rl", str(start), str(count), str(path)],
                       stdout=output, stderr=subprocess.STDOUT, check=True)
    if path.stat().st_size != count * 512:
        raise RuntimeError(f"short read: {path}")
    return digest(path)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "backup/frame157-loader")
    out.mkdir(parents=True, exist_ok=True)
    # Exclusive process lock; the OS releases it on exit or interruption.
    import fcntl
    with (out / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        device = subprocess.check_output([str(TOOL), "ld"], text=True)
        info = subprocess.check_output([str(TOOL), "rfi"], text=True)
        if "Loader" not in device or f"{SECTORS} Sectors" not in info:
            raise RuntimeError(f"expected FRAME157 in Loader mode: {device} {info}")
        (out / "device.txt").write_text(device + info)
        chunks = []
        for start in range(0, SECTORS, CHUNK_SECTORS):
            count = min(CHUNK_SECTORS, SECTORS - start)
            target = out / f"{start:010d}.img"
            proof = target.with_suffix(".json")
            if target.exists() and proof.exists():
                saved = json.loads(proof.read_text())
                if (saved.get("start") == start and saved.get("sectors") == count
                        and target.stat().st_size == count * 512
                        and digest(target) == saved.get("sha256")):
                    print(f"skip verified {start} + {count}", flush=True)
                    chunks.append(target)
                    continue
            began = time.monotonic()
            first = target.with_suffix(".first.part")
            second = target.with_suffix(".second.part")
            print(f"read twice {start} + {count}", flush=True)
            hash1 = read_chunk(start, count, first, out / "read-first.log")
            hash2 = read_chunk(start, count, second, out / "read-second.log")
            if hash1 != hash2:
                raise RuntimeError(f"read mismatch at sector {start}; partials retained")
            os.replace(first, target)
            second.unlink()
            record = {"start": start, "sectors": count, "sha256": hash1,
                      "verification": "two matching reads in loader mode"}
            pending = proof.with_suffix(".json.part")
            pending.write_text(json.dumps(record, indent=2) + "\n")
            os.replace(pending, proof)
            chunks.append(target)
            print(f"verified {start + count}/{SECTORS} sectors, "
                  f"{time.monotonic() - began:.1f}s", flush=True)
        image = out / "mmcblk2-full.img"
        partial = image.with_suffix(".img.part")
        full_hash = hashlib.sha256()
        with partial.open("wb") as dest:
            for chunk in chunks:
                expected = json.loads(chunk.with_suffix(".json").read_text())["sha256"]
                actual = hashlib.sha256()
                with chunk.open("rb") as src:
                    for data in iter(lambda: src.read(4 * 1024 * 1024), b""):
                        actual.update(data)
                        full_hash.update(data)
                        dest.write(data)
                if actual.hexdigest() != expected:
                    raise RuntimeError(f"chunk changed before assembly: {chunk}")
        if partial.stat().st_size != SECTORS * 512 or digest(partial) != full_hash.hexdigest():
            raise RuntimeError("assembled image failed verification")
        os.replace(partial, image)
        (out / "mmcblk2-full.img.sha256").write_text(f"{full_hash.hexdigest()}  {image.name}\n")
        print(f"backup complete: {image}", flush=True)


if __name__ == "__main__":
    main()
