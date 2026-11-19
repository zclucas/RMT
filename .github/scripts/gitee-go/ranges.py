"""Choose a reachable public route before downloading verified byte ranges."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import re
import subprocess
from tempfile import TemporaryDirectory
import time


def piece(url, start, end, size, dest, timeout, retries=0):
    headers = dest.with_suffix(".headers")
    cmd = ["curl", "-q", "-fsSL", "--retry", str(retries), "--connect-timeout", "8",
           "--max-time", str(timeout), "--range", f"{start}-{end}", "-D", str(headers),
           "-o", str(dest), url]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"curl {result.returncode} for bytes {start}-{end}")
    if (dest.stat().st_size != end - start + 1 or not
            re.search(rf"(?im)^content-range:\s*bytes {start}-{end}/{size}\s*$",
                      headers.read_text(encoding="latin-1"))):
        if not (start == 0 and end == size - 1 and dest.stat().st_size == size):
            raise ValueError("unexpected HTTP byte range")


def fetch(url, cdn, path, size):
    routes = {"github": url, "github-cdn": cdn}
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        end = min(size, 128 * 1024) - 1

        def probe(item):
            name, address = item
            # Give each concurrent probe its own lifetime, including late responses.
            with TemporaryDirectory() as probe_dir:
                dest = Path(probe_dir) / "probe"
                start = time.monotonic()
                piece(address, 0, end, size, dest, 18)
                return name, time.monotonic() - start, dest.read_bytes()

        pool = ThreadPoolExecutor(max_workers=3)
        tasks = {pool.submit(probe, item): item[0] for item in routes.items()}
        try:
            for f in as_completed(tasks):
                try:
                    selected, seconds, prefix = f.result()
                    break
                except (RuntimeError, ValueError) as exc:
                    print(f"ROUTE {tasks[f]} unavailable: {exc}", flush=True)
            else:
                raise RuntimeError("no working download route")
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
        print(f"ROUTE selected {selected}, {end+1} bytes in {seconds:.3f}s", flush=True)
        if len(prefix) == size:
            path.write_bytes(prefix)
            return
        routes_by_speed = [selected] + [name for name in routes if name != selected]
        block = 512 * 1024

        def part(start):
            dest = root / f"{start}.part"
            for name in routes_by_speed:
                try:
                    piece(routes[name], start, min(size, start+block)-1, size, dest, 45)
                    return dest
                except (RuntimeError, ValueError) as exc:
                    print(f"RETRY {name} {start}: {exc}", flush=True)
            raise RuntimeError(f"no valid copy of range at {start}")

        with ThreadPoolExecutor(max_workers=8) as pool, path.open("wb") as output:
            output.write(prefix)
            for dest in pool.map(part, range(len(prefix), size, block)):
                output.write(dest.read_bytes())
