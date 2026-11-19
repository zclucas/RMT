"""Mirror GitHub heads and tags, with a lease on each destination ref."""
import os
import subprocess
import tempfile

SOURCE = "https://github.com/zclucas/RMT.git"
TARGET = "https://gitee.com/fateman/RMT.git"


def git(*args, cwd=None):
    command = ["git"]
    if os.environ.get("GITEE_RELEASE_TOKEN"):
        helper = '!f() { if test "$1" = get; then printf "username=oauth2\\npassword=%s\\n" "$GITEE_RELEASE_TOKEN"; fi; }; f'
        command += ["-c", "credential.helper=", "-c", "credential.helper=" + helper]
    return subprocess.check_output(command + list(args), cwd=cwd, text=True)


def refs(url):
    return {ref: sha for sha, ref in (row.split() for row in
            git("ls-remote", "--refs", url, "refs/heads/*", "refs/tags/*").splitlines())}


if __name__ == "__main__":
    source, target = refs(SOURCE), refs(TARGET)
    if source and all(target.get(ref) == sha for ref, sha in source.items()):
        print(f"Verified {len(source)} GitHub refs on Gitee")
        raise SystemExit(0)
    with tempfile.TemporaryDirectory() as directory:
        git("init", "--bare", "--quiet", directory)
        git("fetch", "--quiet", "--no-tags", SOURCE, "+refs/heads/*:refs/heads/*",
            "+refs/tags/*:refs/tags/*", cwd=directory)
        expected = refs(directory)
        before = refs(TARGET)
        changed = [ref for ref in expected if expected[ref] != before.get(ref)]
        if changed:
            git("push", "--atomic", *["--force-with-lease=" + ref + ":" + before.get(ref, "")
                for ref in changed], TARGET, *[ref + ":" + ref for ref in changed], cwd=directory)
        after = refs(TARGET)
        if any(after.get(ref) != sha for ref, sha in expected.items()):
            raise RuntimeError("Gitee branches or tags differ from fetched GitHub snapshot")
        print(f"Verified {len(expected)} GitHub refs on Gitee ({len(changed)} updated)")
