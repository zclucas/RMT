"""Publish GitHub-built RMT ZIPs from the CNB runner and verify public downloads."""
import hashlib
import json
import os
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from time import monotonic
from urllib.request import Request, urlopen


def read_json(url):
    with urlopen(Request(url, headers={"User-Agent": "RMT-release-ci"}), timeout=30) as response:
        return json.load(response)


def download(url, path, size, digest):
    started = monotonic()
    result = hashlib.sha256()
    with urlopen(Request(url, headers={"User-Agent": "RMT-release-ci"}), timeout=90) as response, path.open("wb") as output:
        count = 0
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > size:
                raise ValueError(f"{path.name} exceeds the expected size")
            result.update(block)
            output.write(block)
    if count != size or result.hexdigest() != digest:
        raise ValueError(f"{path.name} size or SHA-256 mismatch")
    print(f"Verified {url}: {count} bytes, SHA-256 {digest}, {monotonic()-started:.1f}s", flush=True)


def publish(tag, target, release_id, attached, asset, directory):
    name, size, digest = asset["name"], asset["size"], asset["digest"]
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest) or not 0 < size <= 100 * 1024**2:
        raise ValueError(f"Invalid GitHub metadata for {name}")
    path = directory / name
    if name not in attached:
        download(f"https://github.com/zclucas/RMT/releases/download/{tag}/{name}", path, size, digest[7:])
        api = f"https://gitee.com/api/v5/repos/{target}/releases/{release_id}/attach_files"
        started = monotonic()
        result = subprocess.run(
            ["curl", "--silent", "--show-error", "--fail", "--http1.1", "--header", "Expect:",
             "--connect-timeout", "15", "--max-time", "360", "--form", "access_token=<-",
             "--form", f"file=@{path};type=application/zip", api],
            input=os.environ["GITEE_RELEASE_TOKEN"].encode(), stdout=subprocess.PIPE, check=True)
        uploaded = json.loads(result.stdout)
        if uploaded.get("name") != name or uploaded.get("size") != size:
            raise ValueError(f"Gitee did not confirm {name}")
        print(f"Uploaded {name} in {monotonic()-started:.1f}s", flush=True)
    download(f"https://gitee.com/{target}/releases/download/{tag}/{name}", path, size, digest[7:])


def main():
    tag = os.environ["RELEASE_TAG"]
    if not re.fullmatch(r"v\d+\.\d+(?:\.\d+)*(?:F\d+)?", tag):
        raise ValueError("Invalid release tag")
    target = os.environ.get("GITEE_TARGET", "fateman/RMT")
    if target not in {"fateman/RMT", "fateman/rmt-release-test"}:
        raise ValueError("Unexpected Gitee repository")
    release = read_json(f"https://gitee.com/api/v5/repos/{target}/releases/tags/{tag}")
    if release["tag_name"] != tag or not isinstance(release["id"], int):
        raise ValueError("Missing Gitee release")
    attached = {a.get("name") for a in release.get("assets", [])}
    assets = json.loads(os.environ["RELEASE_ASSETS"])
    names = {f"RMT{tag}_{arch}.zip" for arch in ("x86", "x64")}
    if len(assets) != 2 or {a["name"] for a in assets} != names:
        raise ValueError("Expected both GitHub release packages")
    with tempfile.TemporaryDirectory() as directory, ThreadPoolExecutor(max_workers=2) as pool:
        jobs = [pool.submit(publish, tag, target, release["id"], attached, asset, Path(directory)) for asset in assets]
        for job in jobs:
            job.result()


if __name__ == "__main__":
    main()
