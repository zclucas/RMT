"""Rebuild GitCode release chronology from verified backups; GitHub stays online."""
from concurrent.futures import ThreadPoolExecutor
import base64
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

import sync_gitcode_assets as mirror


def presentation_plan(store):
    plan = []
    for source in store.releases():
        tag = source['tag_name']
        target = mirror.release(tag)
        if not target:
            raise ValueError('Missing release before backup: ' + tag)
        files = mirror.attachments(target)
        github = {a['name']: a for a in store.assets(tag)}
        expected = set(github)
        if mirror.MODEL in expected:
            expected.remove(mirror.MODEL)
            expected.add(mirror.MODEL + '.parts.json')
        if {a['name'] for a in files} != expected:
            raise ValueError('Provider attachments differ before rebuild: ' + tag)
        for asset in files:
            if asset['name'] in github:
                origin = github[asset['name']]
                if asset['size'] != origin['size'] or asset.get('digest') != origin.get('digest'):
                    raise ValueError('Provider checksum mismatch before rebuild: ' + tag + '/' + asset['name'])
        plan.append(dict(tag=tag, source=source, original=target, assets=files))
    return plan


def stage_backups(store, plan):
    tasks = [(release, asset) for release in plan for asset in release['assets']]

    def stage(task):
        release, asset = task
        tag, name = release['tag'], asset['name']
        if name == mirror.MODEL + '.parts.json':
            path = store.directory / tag / name
            path.parent.mkdir(parents=True, exist_ok=True)
            with urlopen(Request(mirror.public_url(tag, name), headers={'User-Agent': 'RMT-release-backup'}), timeout=90) as response:
                raw = response.read(1024 * 1024 + 1)
            path.write_bytes(raw)
            descriptor = json.loads(raw)
            model = store.asset(tag, mirror.MODEL)
            if (descriptor.get('format') != 'lfs' or descriptor.get('sha256') != model['digest'][7:]
                    or descriptor.get('size') != model['size']):
                raise ValueError('Model descriptor backup mismatch')
            asset['backup_base64'] = base64.b64encode(raw).decode('ascii')
        else:
            origin = store.asset(tag, name)
            path = store.download(tag, origin)
        if path.stat().st_size != asset['size'] or mirror.sha(path) != asset['digest']:
            raise ValueError('Backup checksum mismatch: ' + tag + '/' + name)
        asset['backup_path'] = str(path)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(stage, tasks))


def rebuild_gitcode_releases(store, preview=False):
    plan = presentation_plan(store)
    summary = dict(status='passed', preview=preview,
                   order=[r['tag'] for r in plan],
                   releases=[dict(tag=r['tag'], files=len(r['assets']),
                                  bytes=sum(a['size'] for a in r['assets'])) for r in plan])
    if preview:
        return summary
    # No tags or release metadata are removed until EVERY backup has passed SHA-256.
    stage_backups(store, plan)
    backup = Path(os.environ.get('RUNNER_TEMP', 'Test/output')) / 'resource-rebuild-backup.json'
    backup.write_text(json.dumps(plan, ensure_ascii=True, indent=2), encoding='utf-8')
    checkout = store.directory / 'rebuild-tags'
    mirror.git('init', '--bare', str(checkout))
    mirror.git('fetch', '--quiet', '--depth=1', mirror.REMOTE,
               '+refs/tags/*:refs/tags/*', cwd=checkout)

    def identity(assets):
        return sorted((a['name'], a['size'], a.get('digest')) for a in assets)

    def restore(release, original):
        tag = release['tag']
        current = mirror.git('ls-remote', '--tags', mirror.REMOTE, 'refs/tags/' + tag, cwd=checkout)
        if not current.strip():
            mirror.git('push', '--quiet', mirror.REMOTE, original + ':refs/tags/' + tag, cwd=checkout)
        mirror.ensure_release(release['source'])
        # Uploading performs anonymous full-file readback and SHA-256 verification.
        for asset in release['assets']:
            mirror.upload(tag, Path(asset['backup_path']), asset, max_time=600)
        if identity(mirror.attachments(mirror.release(tag))) != identity(release['assets']):
            raise ValueError('Restored attachment set differs: ' + tag)

    for release in reversed(plan):
        tag = release['tag']
        # Refuse to discard an attachment added or changed after the backup.
        current = mirror.attachments(mirror.release(tag))
        if identity(current) != identity(release['assets']):
            raise ValueError('Release changed after backup: ' + tag)
        original = mirror.git('rev-parse', 'refs/tags/' + tag, cwd=checkout).strip()
        print('Rebuild GitCode release metadata: ' + tag, flush=True)
        try:
            mirror.git('push', '--quiet', mirror.REMOTE, ':refs/tags/' + tag, cwd=checkout)
            restore(release, original)
        except Exception:
            # A transient upload failure must still attempt to restore the current
            # release from the complete local backups before reporting failure.
            restore(release, original)
            raise
    actual = [r['tag_name'] for r in mirror.pages(mirror.gc, '/releases?direction=desc')]
    tags = [r['name'] for r in mirror.pages(mirror.gc, '/tags')]
    if actual != summary['order'] or tags != summary['order']:
        raise ValueError('Rebuilt GitCode chronology differs from GitHub')
    summary.update(release_order=actual, tag_order=tags)
    return summary
