"""Prepare and wait for one native Gitee Go build per published release."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

from mirror_rmt_refs import git

VERSION = r"v[0-9]+(?:\.[0-9]+)+(?:F[0-9]+)?"
SCRIPTS = Path(__file__).resolve().parent / "gitee-go"


def http(url, token=None, data=None, form=False):
    headers = {"User-Agent": "RMT-release-sync"}
    if token:
        headers["Authorization"] = "Bearer " + token
    body = None
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded" if form else "application/json"
        body = (urlencode(data) if form else json.dumps(data)).encode()
    with urlopen(Request(url, body, headers), timeout=60) as res:
        return json.load(res)


def prepare(repo, tag):
    gh = "https://api.github.com/repos/zclucas/" + repo + "/releases"
    source = http(gh + "/tags/" + tag, os.environ["GH_TOKEN"])
    if source["draft"] or source["tag_name"] != tag:
        raise ValueError("Unpublished release " + tag)
    assets = []
    for page in range(1, 101):
        batch = http(f"{gh}/{source['id']}/assets?per_page=100&page={page}", os.environ["GH_TOKEN"])
        for a in batch:
            if (a["state"] != "uploaded" or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]*", a["name"])
                    or not re.fullmatch("sha256:[0-9a-f]{64}", a.get("digest") or "")
                    or not 0 < a["size"] <= 100 * 1024**2):
                raise ValueError("Unsupported GitHub attachment: " + a["name"])
            assets.append({k: a[k] for k in ("name", "digest", "size")})
        if len(batch) < 100:
            break
    names = {a["name"] for a in assets}
    if not assets or len(names) != len(assets) or (repo == "RMT" and
            not {"RMT" + tag + "_" + arch + ".zip" for arch in ("x64", "x86")} <= names):
        raise ValueError("Incomplete release " + tag)
    api = "https://gitee.com/api/v5/repos/fateman/" + repo
    try:
        target = http(api + "/releases/tags/" + tag, os.environ["GITEE_RELEASE_TOKEN"])
    except HTTPError as exc:
        if exc.code != 404:
            raise
        target = None
    if not target:
        ref = "refs/tags/" + tag
        remote = "https://gitee.com/fateman/" + repo + ".git"
        if not git("ls-remote", "--refs", remote, ref).strip():
            if repo == "RMT":
                raise ValueError("Mirror the source tag first")
            http(api + "/tags", data=dict(access_token=os.environ["GITEE_RELEASE_TOKEN"],
                 tag_name=tag, refs="main"), form=True)
        target = http(api + "/releases", data=dict(access_token=os.environ["GITEE_RELEASE_TOKEN"],
                      tag_name=tag, target_commitish=tag, name=source["name"] or tag,
                      body=source["body"] or tag, prerelease=str(source["prerelease"]).lower()), form=True)
    if target["tag_name"] != tag or target["prerelease"] != source["prerelease"]:
        raise ValueError("Gitee release identity mismatch " + tag)
    existing = {a.get("name") for a in target["assets"]}
    return dict(repo=repo, tag=tag, assets=assets, missing=sorted(names-existing),
                title=source["name"] or tag, body=source["body"] or tag, prerelease=source["prerelease"])


def pipeline(m):
    def step(name, **kwargs):
        return {"step": "build@python", "name": name, "displayName": name,
                "pythonVersion": "3.9", "commands": ["python3 ci/transfer.py " + name], **kwargs}
    steps = []
    if m["missing"]:
        steps.append(step("download", artifacts=[{"name": "PACKAGES", "path": m["missing"]}]))
        steps.append(dict(step="release@gitee", name="upload", displayName="upload", dependsOn="download",
                          releaseName=m["title"], tagName=m["tag"], description=m["body"],
                          prerelease=m["prerelease"], allowUpdate=True, upstreamArtifact=["PACKAGES"],
                          assertFiles=m["missing"]))
    steps.append(step("readback", **({"dependsOn": "upload"} if steps else {})))
    return {"version": "1.0", "name": "rmt-sync", "displayName": "RMT Release SHA-256",
            "triggers": {"trigger": "manual"}, "strategy": {"timeout": 60}, "stages": [
                dict(name="sync", displayName="Sync", trigger="auto", strategy="naturally", steps=steps)]}


def go_stage(base, stage_id):
    api = base.rsplit("/builds", 1)[0]
    reply = http(f"{api}/stages/builds/{int(stage_id)}", os.environ["GITEE_RELEASE_TOKEN"])
    if reply.get("code") != 0:
        raise RuntimeError("Gitee Go step logs unavailable")
    return reply["data"]


def dispatch(m):
    import yaml
    repo, tag = m["repo"], m["tag"]
    remote = "https://gitee.com/fateman/" + repo + ".git"
    branch = f"ci/rmt-release-{tag}-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        git("init", "-q", "-b", branch, tmp)
        (root / ".workflow").mkdir(exist_ok=True)
        shutil.copytree(SCRIPTS, root / "ci", dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__"))
        (root / "manifest.json").write_text(json.dumps(m, ensure_ascii=True), encoding="utf8")
        (root / ".workflow/rmt-sync.yml").write_text(yaml.safe_dump(pipeline(m), sort_keys=False,
                allow_unicode=True), encoding="utf8")
        git("add", "--", ".workflow", "ci", "manifest.json", cwd=root)
        if git("status", "--porcelain", cwd=root).strip():
            git("-c", "user.name=RMT release", "-c", "user.email=release@users.noreply.github.com",
                "commit", "-qm", "Sync " + tag, cwd=root)
            git("push", remote, "HEAD:refs/heads/" + branch, cwd=root)
        commit = git("rev-parse", "HEAD", cwd=root).strip()
        ref = "refs/heads/" + branch
        try:
            wait_for_build(m, branch)
        finally:
            git("push", "--force-with-lease=" + ref + ":" + commit, remote, ":" + ref, cwd=root)


def wait_for_build(m, branch):
    repo, tag = m["repo"], m["tag"]
    base = "https://go-api.gitee.com/fateman/" + repo + "/gitee-go/ipipe/rest/v5/pipelines/builds"
    def go(path, data=None):
        res = http(base + path, os.environ["GITEE_RELEASE_TOKEN"], data)
        if res.get("code") != 0:
            raise RuntimeError(f"Gitee Go {res.get('code')}: {res.get('msg')}")
        return res["data"]
    build = int(go("", dict(fileName="rmt-sync.yml", ref=branch, params=[]))["id"])
    print(f"{repo}/{tag}: Gitee Go {build}", flush=True)
    deadline = time.monotonic() + 65 * 60
    while time.monotonic() < deadline:
        current = go(f"/{build}/status")
        status = current["status"]
        if status in {"SUCCESS", "SUCCEEDED"}:
            expected = {f"readback {repo}/{tag}/{a['name']} {a['size']} {a['digest'][7:]}"
                        for a in m["assets"]}
            seen = set()
            for stage in current["stages"]:
                detail = go_stage(base, stage["id"])
                for group in detail["jobs"]:
                    for job in group:
                        for entry in (job.get("record") or {}).get("stages") or []:
                            url = entry.get("logger") or ""
                            if entry["plugin"].startswith("SYSTEM_") or (urlsplit(url).scheme,
                                    urlsplit(url).netloc) != ("https", "go-api.gitee.com"):
                                continue
                            logs = http(url, os.environ["GITEE_RELEASE_TOKEN"])
                            for line in (logs.get("data") or {}).get("logs", []):
                                seen.update(proof for proof in expected if proof in line)
            if seen != expected:
                raise RuntimeError(f"Gitee Go {build} missing readback receipts for {expected - seen}")
            with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf8") as summary:
                print(f"### {repo} · {tag} · Gitee Go {build}\n", file=summary)
                for line in sorted(seen):
                    print(f"- `{line}`", file=summary)
            print(f"Gitee Go {build} verified {len(m['assets'])} attachments", flush=True)
            return
        if status in {"FAILED", "FAIL", "CANCELED", "CANCELLED", "ERROR", "STOPPED", "TIMEOUT"}:
            raise RuntimeError(f"Gitee Go {build}: {status}")
        time.sleep(10)
    raise TimeoutError(f"Gitee Go {build}")


if __name__ == "__main__":
    tag = os.environ["RELEASE_TAG"]
    if not re.fullmatch(VERSION, tag):
        raise ValueError("Invalid release tag")
    tags = json.loads(os.environ.get("ASSET_TAGS") or "null")
    arch = {tag + "_x64", tag + "_x86"}
    if tags is None:
        tags = sorted(arch)
    if not arch <= set(tags) <= arch | {"Common"} or len(tags) != len(set(tags)):
        raise ValueError("Unexpected resource releases")
    manifests = [prepare("RMT", tag)] + [prepare("RMTAssets", ref) for ref in tags]
    for manifest in manifests:
        if sys.argv[1] == "go":
            dispatch(manifest)
        elif sys.argv[1] == "relay":
            subprocess.run(["bash", ".github/scripts/gitee-relay.sh"], input=json.dumps(
                {k: manifest[k] for k in ("repo", "tag", "assets")}).encode(), check=True)
        else:
            raise ValueError("Unknown mode")
