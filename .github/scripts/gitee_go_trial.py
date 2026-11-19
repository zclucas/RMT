"""Dispatch the independent Gitee Go benchmark after GitHub publishes both releases."""
import json
import os
import re
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

API = "https://go-api.gitee.com/fateman/RMTAssets/gitee-go/ipipe/rest/v5"
tag = os.environ["RELEASE_TAG"]
if not re.fullmatch(r"v\d+(?:\.\d+)+(?:F\d+)?", tag):
    raise ValueError("Invalid RMT release tag")
trial_tag = f"go-trial-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"


def request(url, token, data=None):
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json",
               "Accept": "application/json", "User-Agent": "RMT-Gitee-Go"}
    req = Request(url, headers=headers, data=json.dumps(data).encode() if data else None)
    with urlopen(req, timeout=45) as response:
        return json.load(response)


def go(path, data=None):
    reply = request(API + path, os.environ["GITEE_RELEASE_TOKEN"], data)
    if reply.get("code") != 0 or not reply.get("data"):
        raise RuntimeError(f"Gitee Go {path}: {reply.get('code')} {reply.get('msg')}")
    return reply["data"]


params = {"RELEASE_TAG": tag, "TRIAL_TAG": trial_tag}
for repo, ref, name, param in [
    ("RMT", tag, f"RMT{tag}_x64.zip", "PACKAGE_SHA"),
    ("RMTAssets", tag + "_x64", "RMT.zip", "RESOURCE_SHA"),
]:
    release = request(f"https://api.github.com/repos/zclucas/{repo}/releases/tags/{ref}", os.environ["GH_TOKEN"])
    asset = next(a for a in release["assets"] if a["name"] == name and a["state"] == "uploaded")
    if release["draft"] or not re.fullmatch(r"sha256:[a-f0-9]{64}", asset["digest"] or ""):
        raise ValueError(f"Unpublished release or missing digest: {repo}/{ref}/{name}")
    params[param] = asset["digest"][7:]
    params[param.replace("_SHA", "_BYTES")] = str(asset["size"])

build = go("/pipelines/builds", {"fileName": "rmt-go-trial.yml", "ref": "codex/gitee-go-trial",
                                "params": [{"key": k, "name": k, "value": v} for k, v in params.items()]})
build_id = int(build["id"])
print(f"Gitee Go build {build_id}, release {tag}, trial tag {trial_tag}", flush=True)
with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
    print(f"Gitee Go build **{build_id}** · {tag} · {trial_tag}", file=summary)
def report(stages):
    lines = []
    for stage in stages:
        detail = go(f"/pipelines/stages/builds/{int(stage['id'])}")
        for group in detail["jobs"]:
            for job in group:
                record = job.get("record") or {}
                for step in record.get("stages") or []:
                    plugin = step["plugin"]
                    if plugin.startswith("SYSTEM_"):
                        continue
                    started, ended = step.get("realStartTime"), step.get("finishTime")
                    if plugin.startswith("gitee-release@") and started and ended:
                        lines.append(f"Upload plugin: {(ended - started) / 1000:.1f}s (includes plugin processing)")
                    url = step.get("logger") or ""
                    parsed = urlsplit(url)
                    if (parsed.scheme, parsed.netloc) != ("https", "go-api.gitee.com"):
                        continue
                    log = request(url, os.environ["GITEE_RELEASE_TOKEN"])
                    for text in (log.get("data") or {}).get("logs", []):
                        if " MEASURE " in text:
                            lines.append(text.split(" MEASURE ", 1)[1].strip())
    for line in lines:
        print(line)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        for line in lines:
            print(f"- `{line}`", file=summary)


deadline = time.monotonic() + 18 * 60
while time.monotonic() < deadline:
    current = go(f"/pipelines/builds/{build_id}/status")
    status = current["status"]
    if status in ("SUCCESS", "SUCCEEDED"):
        report(current["stages"])
        print("Gitee Go readback passed")
        break
    if status in ("FAILED", "FAIL", "CANCELED", "CANCELLED", "ERROR", "STOPPED", "TIMEOUT"):
        report(current["stages"])
        raise RuntimeError(f"Gitee Go build {build_id}: {status}")
    time.sleep(12)
else:
    raise TimeoutError(f"Gitee Go build {build_id} did not complete")
