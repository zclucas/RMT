"""Run inside Gitee Go, using the public release manifest committed with this pipeline."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import quote
from ranges import fetch


def transfer(item):
    repo, tag = manifest["repo"], manifest["tag"]
    name = item["name"]
    suffix = "/releases/download/" + quote(tag, safe="") + "/" + quote(name, safe="")
    with tempfile.TemporaryDirectory() as tmp:
        if mode == "download":
            path = Path(name)
            url = "https://github.com/zclucas/" + repo + suffix
            fetch(url, "https://ghfile.geekertao.top/" + url, path, item["size"])
        else:
            path = Path(tmp) / "attachment"
            subprocess.run(["curl", "-q", "-fsSL", "--retry", "2", "--connect-timeout", "20",
                            "--max-time", "420", "-o", str(path),
                            "https://gitee.com/fateman/" + repo + suffix], check=True)
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        if path.stat().st_size != item["size"] or "sha256:" + digest.hexdigest() != item["digest"]:
            raise ValueError(f"{mode} mismatch for {repo}/{tag}/{name}")
        print(f"{mode} {repo}/{tag}/{name} {path.stat().st_size} {digest.hexdigest()}", flush=True)


manifest = json.loads(Path("manifest.json").read_text())
mode = sys.argv[1]
if mode not in ("download", "readback"):
    raise ValueError(mode)
with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(transfer, [item for item in manifest["assets"] if mode == "readback" or
                             item["name"] in manifest["missing"]]))
