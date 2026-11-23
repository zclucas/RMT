"""Mirror GitHub heads and tags, with a lease on each destination ref."""
import os
import subprocess
import tempfile

SOURCE = "https://github.com/zclucas/RMT.git"
TARGET = "https://gitcode.com/ruomengtu/RMT.git"


def git(*args, cwd=None, timeout=None):
    command = ["git"]
    if os.environ.get("GITCODE_TOKEN"):
        helper = '!f() { if test "$1" = get; then printf "username=ruomengtu\\npassword=%s\\n" "$GITCODE_TOKEN"; fi; }; f'
        command += ["-c", "credential.helper=", "-c", "credential.https://gitcode.com.helper=" + helper]
    return subprocess.check_output(command + list(args), cwd=cwd, text=True, timeout=timeout)


def refs(url):
    return {ref: sha for sha, ref in (row.split() for row in
            git("ls-remote", "--refs", url, "refs/heads/*", "refs/tags/*").splitlines())}


def set_default_branch():
    from sync_gitcode_assets import api
    line = next(row for row in git("ls-remote", "--symref", SOURCE, "HEAD").splitlines() if row.startswith("ref: "))
    branch = line.split()[1].removeprefix("refs/heads/")
    api("https://api.gitcode.com/api/v5/repos/ruomengtu/RMT", os.environ["GITCODE_TOKEN"], "",
        data=dict(name="RMT", default_branch=branch), method="PATCH")


if __name__ == "__main__":
    source, target = refs(SOURCE), refs(TARGET)
    if source and all(target.get(ref) == sha for ref, sha in source.items()):
        print(f"Verified {len(source)} GitHub refs on GitCode")
        set_default_branch()
        raise SystemExit(0)
    with tempfile.TemporaryDirectory() as directory:
        git("init", "--bare", "--quiet", directory)
        git("fetch", "--quiet", "--no-tags", SOURCE, "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*", cwd=directory)
        expected = refs(directory)
        before = refs(TARGET)
        changed = [ref for ref in expected if expected[ref] != before.get(ref)]
        if changed:
            git("push", *["--force-with-lease=" + ref + ":" + before.get(ref, "")
                for ref in changed], TARGET, *[ref + ":" + ref for ref in changed], cwd=directory)
        after = refs(TARGET)
        if any(after.get(ref) != sha for ref, sha in expected.items()):
            raise RuntimeError("GitCode branches or tags differ from fetched GitHub snapshot")
        print(f"Verified {len(expected)} GitHub refs on GitCode ({len(changed)} updated)")

    set_default_branch()
