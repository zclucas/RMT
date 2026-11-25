"""Publish original RMTAssets files to GitCode; the large model has explicit fallbacks."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import Request, urlopen
import zipfile
from resource_policy import mutable_tag, catalog_additions

REPO = 'RMTAssets'
SOURCE = 'https://api.github.com/repos/zclucas/' + REPO
TARGET = 'https://api.gitcode.com/api/v5/repos/ruomengtu/RMTAssets'
REMOTE = 'https://gitcode.com/ruomengtu/RMTAssets.git'
PUBLIC = 'https://gitcode.com/ruomengtu/RMTAssets/releases/download/'
MODEL = 'Index-Translate-2B.Q4_K_M.gguf'
PART_BYTES = 195_000_000
API_LOCK = threading.Lock()
API_NEXT = 0.0


def rate_wait():
    global API_NEXT
    with API_LOCK:
        now = time.monotonic()
        delay = max(0.0, API_NEXT - now)
        API_NEXT = max(API_NEXT, now) + 1.2
    if delay:
        time.sleep(delay)


def retry_delay(exc, attempt):
    if isinstance(exc, HTTPError) and exc.code == 429:
        value = exc.headers.get('Retry-After', '') if exc.headers else ''
        return max(60, int(value)) if value.isdigit() else 60 * (attempt + 1)
    return 5 * (attempt + 1)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return 'sha256:' + digest.hexdigest()


def safe_name(name):
    if not name or name in ('.', '..') or any(c in name for c in '/\\\r\n'):
        raise ValueError('Invalid attachment name')
    return name


def api(base, token, path, data=None, method=None):
    headers = {'Authorization': 'Bearer ' + token, 'User-Agent': 'RMT-resource-sync'}
    body = None
    if data is not None:
        headers['Content-Type'] = 'application/json'
        body = json.dumps(data).encode('utf-8')
    for attempt in range(6):
        try:
            if base == TARGET:
                rate_wait()
            with urlopen(Request(base + path, body, headers, method=method), timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504) or attempt == 5:
                raise
            delay = retry_delay(exc, attempt)
        except (URLError, TimeoutError):
            if attempt == 5:
                raise
            delay = 5 * (attempt + 1)
        time.sleep(delay)


def gh(path, **kwargs):
    return api(SOURCE, os.environ['GH_TOKEN'], path, **kwargs)


def gc(path, **kwargs):
    return api(TARGET, os.environ['GITCODE_TOKEN'], path, **kwargs)


def pages(get, path):
    result = []
    for page in range(1, 101):
        batch = get(path + ('&' if '?' in path else '?') + urlencode(dict(per_page=100, page=page)))
        if not isinstance(batch, list):
            raise ValueError('Unexpected pagination response')
        result.extend(batch)
        if len(batch) < 100:
            return result
    raise ValueError('Pagination exceeded its bound')


def attachments(release):
    return [a for a in (release or {}).get('assets', []) if a.get('type') == 'attach']


def release(tag):
    return next((r for r in pages(gc, '/releases') if r['tag_name'] == tag), None)


def release_metadata(source):
    # GitCode pins "latest" before newer previews; use chronological display like GitHub.
    return dict(name=source.get('name') or source['tag_name'], body=source.get('body') or source['tag_name'],
                release_status='pre' if source.get('prerelease') else 'none')


def ensure_release(source):
    tag = source['tag_name']
    current = release(tag)
    metadata = release_metadata(source)
    if current:
        if any(current.get(k) != v for k, v in metadata.items()):
            return gc('/releases/' + quote(tag, safe=''), data=metadata, method='PATCH')
        return current
    metadata.update(tag_name=tag, target_commitish=tag if REPO == 'RMT' else 'main')
    creation = dict(metadata, release_status='pre' if source.get('prerelease') else 'latest')
    try:
        created = gc('/releases', data=creation)
        if metadata['release_status'] == 'none':
            created = gc('/releases/' + quote(tag, safe=''), data=release_metadata(source), method='PATCH')
        return created
    except HTTPError as exc:
        if exc.code not in (400, 409, 422) or not release(tag):
            raise
        return release(tag)


def sync_metadata():
    sources = [r for r in pages(gh, '/releases') if not r['draft']]
    for source in reversed(sources):
        if release(source['tag_name']):
            ensure_release(source)
    wanted = [r['tag_name'] for r in sources]
    actual = [r['tag_name'] for r in pages(gc, '/releases?direction=desc')]
    if actual != wanted:
        raise ValueError('Release chronology differs: expected {}, found {}'.format(wanted, actual))
    return dict(status='passed', repo=REPO, release_order=actual)


def public_url(tag, name):
    return PUBLIC + quote(tag, safe='') + '/' + quote(safe_name(name), safe='')


def readback(tag, asset, url=None, headers=None):
    address = url or public_url(tag, asset['name'])
    size = asset['size']
    digest = hashlib.sha256()
    if size > 16 * 1024 * 1024:
        ranges = [(start, min(4 * 1024 * 1024, size - start)) for start in range(0, size, 4 * 1024 * 1024)]

        def fetch(item):
            start, length = item
            for attempt in range(6):
                try:
                    request = Request(address, headers={**(headers or {}), 'Range': 'bytes={}-{}'.format(start, start + length - 1),
                                                       'User-Agent': 'RMT-AssetDownloader/1'})
                    with urlopen(request, timeout=90) as response:
                        expected = 'bytes {}-{}/{}'.format(start, start + length - 1, size)
                        if response.status != 206 or response.headers.get('Content-Range') != expected:
                            raise ValueError('Unexpected public range response')
                        block = response.read(length + 1)
                    if len(block) != length:
                        raise ValueError('Truncated public range')
                    return block
                except HTTPError as exc:
                    if exc.code != 429 or attempt == 5:
                        raise
                    time.sleep(retry_delay(exc, attempt))
                except (OSError, ValueError):
                    if attempt == 5:
                        raise
                    time.sleep(2)
        with ThreadPoolExecutor(max_workers=6) as pool:
            for block in pool.map(fetch, ranges):
                digest.update(block)
    else:
        for attempt in range(6):
            try:
                with urlopen(Request(address, headers={**(headers or {}), 'User-Agent': 'RMT-AssetDownloader/1'}), timeout=90) as response:
                    raw = response.read(size + 1)
                break
            except HTTPError as exc:
                if exc.code != 429 or attempt == 5:
                    raise
                time.sleep(retry_delay(exc, attempt))
        if len(raw) != size:
            raise ValueError('Unexpected public attachment length')
        digest.update(raw)
    if 'sha256:' + digest.hexdigest() != asset['digest']:
        raise ValueError('Public attachment checksum differs from the verified source')
    print('verified {} {} {} {}'.format(tag, asset['name'], size, asset['digest']), flush=True)


def download(tag, asset, directory):
    name = safe_name(asset['name'])
    path = Path(directory) / name
    subprocess.run(['gh', 'release', 'download', tag, '--repo', 'zclucas/' + REPO, '--pattern', name,
                    '--dir', str(directory), '--clobber'], check=True)
    actual = sha(path)
    if path.stat().st_size != asset['size'] or (asset.get('digest') and actual != asset['digest']):
        raise ValueError('GitHub original failed size or checksum verification')
    return path, dict(asset, digest=actual)


def curl_quote(value):
    if '\r' in value or '\n' in value:
        raise ValueError('Unexpected upload configuration line break')
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def upload(tag, path, expected, max_time=5400):
    if Path(path).stat().st_size != expected['size'] or sha(path) != expected['digest']:
        raise ValueError('Upload source changed')
    current = release(tag)
    existing = [a for a in attachments(current) if a['name'] == expected['name']]
    if existing:
        try:
            readback(tag, expected)
            return expected
        except HTTPError as exc:
            if exc.code != 404:
                raise
        except ValueError:
            pass
        for old in existing:
            if not mutable_tag(tag):
                allowed = False
                if expected['name'] == 'A-Assets.json':
                    with urlopen(Request(public_url(tag, expected['name']),
                            headers={'User-Agent': 'RMT-append-only-check'}), timeout=90) as response:
                        allowed = catalog_additions(response.read(16 * 1024 * 1024), Path(path).read_bytes())
                if not allowed:
                    raise ValueError('Stable GitCode assets are append-only: ' + tag + '/' + expected['name'])
            gc('/releases/' + quote(tag, safe='') + '/attach_files/' + str(int(old['id'])), method='DELETE')
    target = gc('/releases/' + quote(tag, safe='') + '/upload_url?' + urlencode({'file_name': expected['name']}))
    if urlsplit(target['url']).scheme != 'https':
        raise ValueError('Upload requires HTTPS')
    with tempfile.TemporaryDirectory(prefix='rmt-upload-', dir=os.environ.get('RUNNER_TEMP')) as directory:
        config = Path(directory) / 'curl.conf'
        lines = ['url = ' + curl_quote(target['url'])]
        lines.extend('header = ' + curl_quote(k + ': ' + v) for k, v in target['headers'].items())
        config.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        config.chmod(0o600)
        print('uploading {} {} {} bytes'.format(tag, expected['name'], expected['size']), flush=True)
        result = subprocess.run(['curl', '--config', str(config), '--upload-file', str(path), '--http1.1', '--ipv4',
                                 '--header', 'Expect:', '--show-error', '--fail',
                                 '--connect-timeout', '30', '--max-time', str(max_time),
                                 '--speed-limit', '32768', '--speed-time', '90',
                                 '--retry', '2', '--retry-all-errors', '--retry-delay', '5',
                                 '--retry-max-time', str(max_time),
                                 '--output', str(Path(directory) / 'response')], timeout=max_time + 30)
        if result.returncode:
            raise RuntimeError('GitCode object upload failed (curl {})'.format(result.returncode))
    for attempt in range(10):
        found = [a for a in attachments(release(tag)) if a['name'] == expected['name']]
        if len(found) == 1 and found[0].get('size') == expected['size']:
            break
        time.sleep(3)
    else:
        raise ValueError('Upload callback did not confirm the expected attachment')
    readback(tag, expected)
    return expected


def mirror_asset(tag, asset):
    if asset.get('digest'):
        target = release(tag)
        if any(a['name'] == asset['name'] for a in attachments(target)):
            try:
                readback(tag, asset)
                return dict(tag=tag, **{k: asset[k] for k in ('name', 'size', 'digest')})
            except HTTPError as exc:
                if exc.code != 404:
                    raise
            except ValueError:
                pass
    with tempfile.TemporaryDirectory(prefix='rmt-source-', dir=os.environ.get('RUNNER_TEMP')) as directory:
        path, verified = download(tag, asset, directory)
        upload(tag, path, verified)
        return dict(tag=tag, **{k: verified[k] for k in ('name', 'size', 'digest')})


def sync(tags=None, asset_name='', workers=4):
    sources = [r for r in pages(gh, '/releases') if not r['draft'] and (not tags or r['tag_name'] in tags)]
    if not sources or (tags and set(tags) != {r['tag_name'] for r in sources}):
        raise ValueError('A selected published release is absent')
    tasks = []
    expected_by_tag = {}
    # Initialize old releases first so creation order follows GitHub chronology.
    for source in reversed(sources):
        tag = source['tag_name']
        originals = [a for a in pages(gh, '/releases/' + str(source['id']) + '/assets')
                     if a.get('state') == 'uploaded' and not re.search(r'\.(?:parts\.json|part\d{4})$', a['name']) and (REPO != 'RMTAssets' or a['name'] != MODEL)
                     and (not asset_name or a['name'] == asset_name)]
        if not originals and asset_name:
            raise ValueError('Selected ordinary original attachment is absent')
        ensure_release(source)
        expected_by_tag[tag] = (source, originals)
        tasks.extend((tag, asset) for asset in originals)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        receipts = list(pool.map(lambda task: mirror_asset(*task), tasks))
    if REPO == 'RMT' and not asset_name:
        # Prune only after every source file has passed full public readback.
        for tag, (source, originals) in expected_by_tag.items():
            if not mutable_tag(tag):
                continue
            latest = [a for a in pages(gh, '/releases/' + str(source['id']) + '/assets') if a.get('state') == 'uploaded']
            fingerprint = lambda assets: sorted((a['id'], a['name'], a['size'], a.get('digest')) for a in assets)
            if fingerprint(latest) != fingerprint(originals):
                raise ValueError('GitHub release changed during synchronization')
            names = {a['name'] for a in originals}
            for stale in attachments(release(tag)):
                if stale['name'] not in names:
                    gc('/releases/' + quote(tag, safe='') + '/attach_files/' + str(int(stale['id'])), method='DELETE')
    return receipts



def retire_sponsor_logo():
    """Retire only Common/rmt.png after both public ZIPs preserve its bytes."""
    tag, name = 'Common', 'rmt.png'
    source = gh('/releases/tags/' + tag)
    target = release(tag)
    if source.get('draft') or not target:
        raise ValueError('Both published Common releases are required')
    github_assets = pages(gh, '/releases/' + str(source['id']) + '/assets')
    gitcode_assets = attachments(target)

    def public_bytes(url):
        with urlopen(Request(url, headers={'User-Agent': 'RMT-sponsor-cleanup'}), timeout=90) as response:
            data = response.read(64 * 1024 * 1024 + 1)
        if len(data) > 64 * 1024 * 1024:
            raise ValueError('Sponsor attachment exceeds verification bound')
        return data

    def one(assets, asset_name, required=False):
        found = [a for a in assets if a['name'] == asset_name]
        if len(found) > 1 or (required and not found):
            raise ValueError('Missing or duplicate sponsor attachment: ' + asset_name)
        return found[0] if found else None

    github_zip = one(github_assets, 'Sponsor.zip', True)
    gitcode_zip = one(gitcode_assets, 'Sponsor.zip', True)
    payload = public_bytes(github_zip['browser_download_url'])
    expected = 'sha256:' + hashlib.sha256(payload).hexdigest()
    if github_zip.get('digest') != expected or github_zip['size'] != len(payload):
        raise ValueError('GitHub Sponsor.zip metadata mismatch')
    if gitcode_zip['size'] != len(payload) or public_bytes(public_url(tag, 'Sponsor.zip')) != payload:
        raise ValueError('Public Sponsor.zip differs between providers')
    with zipfile.ZipFile(io.BytesIO(payload)) as bundle:
        entries = [entry for entry in bundle.infolist() if entry.filename == name]
        if len(entries) != 1 or entries[0].file_size > 64 * 1024 * 1024:
            raise ValueError('Sponsor.zip must contain one root rmt.png')
        image = bundle.read(entries[0])
    if not image.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Archived rmt.png is not a PNG')
    old_github = one(github_assets, name)
    old_gitcode = one(gitcode_assets, name)
    # Finish every preservation check before the first deletion.
    for asset, url in ((old_github, old_github['browser_download_url'] if old_github else ''),
                       (old_gitcode, public_url(tag, name))):
        if asset and (asset['size'] != len(image) or public_bytes(url) != image):
            raise ValueError('Loose rmt.png differs from the archived image')
    removed = []
    if old_gitcode:
        gc('/releases/Common/attach_files/' + str(int(old_gitcode['id'])), method='DELETE')
        removed.append('GitCode/Common/rmt.png')
    if old_github:
        gh('/releases/assets/' + str(int(old_github['id'])), method='DELETE')
        removed.append('GitHub/Common/rmt.png')
    if one(pages(gh, '/releases/' + str(source['id']) + '/assets'), name) or one(attachments(release(tag)), name):
        raise ValueError('Loose sponsor attachment remains after deletion')
    if public_bytes(github_zip['browser_download_url']) != payload or public_bytes(public_url(tag, 'Sponsor.zip')) != payload:
        raise ValueError('Sponsor.zip changed during cleanup')
    return dict(status='passed', removed=removed, sponsor_zip_sha256=expected[7:])


def git(*args, cwd=None, timeout=90):
    helper = '!f() { if test "$1" = get; then printf "username=ruomengtu\\npassword=%s\\n" "$GITCODE_TOKEN"; fi; }; f'
    command = ['git', '-c', 'credential.helper=', '-c', 'credential.https://gitcode.com.helper=' + helper]
    command += list(args)
    if os.name == 'posix' and shutil.which('timeout'):
        command = ['timeout', '--kill-after=5', str(timeout)] + command
    return subprocess.check_output(command, cwd=cwd, text=True, timeout=timeout + 15,
                                   env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GIT_LFS_SKIP_SMUDGE='1'))


def try_lfs(path, asset, directory):
    try:
        gc('', data=dict(name='RMTAssets', lfs_enabled=True), method='PATCH')
    except HTTPError as exc:
        if exc.code not in (400, 403, 404, 405, 422):
            raise
        print('LFS setting API HTTP {}; testing the Git LFS endpoint directly'.format(exc.code), flush=True)
    checkout = Path(directory) / 'lfs'
    git('clone', '--quiet', '--depth', '1', REMOTE, str(checkout))
    before = git('rev-parse', 'HEAD', cwd=checkout).strip()
    relative = 'Common/' + MODEL
    (checkout / 'Common').mkdir(exist_ok=True)
    shutil.copyfile(path, checkout / relative)
    git('lfs', 'install', '--local', cwd=checkout)
    git('lfs', 'track', relative, cwd=checkout)
    git('add', '.gitattributes', relative, cwd=checkout)
    if git('status', '--porcelain', cwd=checkout).strip():
        git('-c', 'user.name=RMT resources', '-c', 'user.email=resources@users.noreply.github.com',
            'commit', '-qm', 'Store translation model with Git LFS', cwd=checkout)
    pushed = False
    try:
        git('-c', 'lfs.dialtimeout=20', '-c', 'lfs.activitytimeout=60', '-c', 'lfs.transfer.maxretries=1',
            'lfs', 'push', 'origin', 'main', cwd=checkout, timeout=600)
        git('push', REMOTE, 'HEAD:refs/heads/main', cwd=checkout, timeout=90)
        pushed = True
        current = git('rev-parse', 'HEAD', cwd=checkout).strip()
        endpoint = REMOTE + '/info/lfs/objects/batch'
        payload = dict(operation='download', transfers=['basic'], objects=[dict(oid=asset['digest'][7:], size=asset['size'])])
        request = Request(endpoint, data=json.dumps(payload).encode(), method='POST',
                          headers={'Content-Type': 'application/vnd.git-lfs+json', 'Accept': 'application/vnd.git-lfs+json',
                                   'User-Agent': 'git-lfs/3.7.1 (RMT)'})
        with urlopen(request, timeout=60) as response:
            batch = json.load(response)
        objects = batch.get('objects') or []
        if len(objects) != 1 or objects[0].get('oid') != asset['digest'][7:] or objects[0].get('size') != asset['size']:
            raise ValueError('Unexpected anonymous LFS object metadata')
        action = (objects[0].get('actions') or {}).get('download') or {}
        if urlsplit(action.get('href') or '').scheme != 'https':
            raise ValueError('No public HTTPS LFS download action')
        headers = dict(action.get('header') or {})
        headers['Range'] = 'bytes=0-4095'
        with urlopen(Request(action['href'], headers=headers), timeout=60) as response:
            raw = response.read(4096)
            total = response.headers.get('Content-Range') or response.headers.get('Content-Length')
        with path.open('rb') as source:
            if raw != source.read(4096) or str(asset['size']) not in str(total):
                raise ValueError('Public LFS action does not serve the original model bytes')
        ensure_release(gh('/releases/tags/Common'))
        descriptor = dict(version=1, format='lfs', name=MODEL, size=asset['size'], sha256=asset['digest'][7:], lfs_endpoint=endpoint)
        descriptor_path = Path(directory) / (MODEL + '.parts.json')
        descriptor_path.write_text(json.dumps(descriptor, indent=2), encoding='utf-8')
        upload('Common', descriptor_path, dict(name=descriptor_path.name, size=descriptor_path.stat().st_size, digest=sha(descriptor_path)))
        return dict(transport='lfs', url=public_url('Common', MODEL), size=asset['size'], sha256=asset['digest'][7:], commit=current)
    except Exception:
        if pushed:
            current = git('rev-parse', 'HEAD', cwd=checkout).strip()
            git('push', '--force-with-lease=refs/heads/main:' + current, REMOTE, before + ':refs/heads/main', cwd=checkout)
        raise


def cleanup_model(names):
    current = release('Common')
    for item in sorted(attachments(current), key=lambda a: not a['name'].endswith('.parts.json')):
        if item['name'] in names:
            gc('/releases/Common/attach_files/' + str(int(item['id'])), method='DELETE')


def try_zip(path, asset, directory):
    archive = Path(directory) / (MODEL + '.zip')
    descriptor_path = Path(directory) / (archive.name + '.parts.json')
    before = {a['name'] for a in attachments(release('Common'))}
    if {archive.name, descriptor_path.name} <= before:
        with urlopen(Request(public_url('Common', descriptor_path.name), headers={'User-Agent': 'RMT-AssetDownloader/1'}), timeout=60) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError('Oversized ZIP descriptor')
        previous = json.loads(raw)
        unpacked = previous.get('unpacked') or {}
        if (previous.get('version') == 1 and previous.get('format') == 'zip' and previous.get('name') == archive.name
                and unpacked.get('name') == MODEL and unpacked.get('size') == asset['size']
                and unpacked.get('sha256') == asset['digest'][7:]
                and isinstance(previous.get('size'), int) and previous['size'] > 0
                and re.fullmatch('[0-9a-f]{64}', previous.get('sha256') or '')):
            readback('Common', dict(name=archive.name, size=previous['size'], digest='sha256:' + previous['sha256']))
            return dict(transport='zip', url=public_url('Common', archive.name), size=asset['size'], sha256=asset['digest'][7:],
                        archive_size=previous['size'], archive_sha256=previous['sha256'])
    info = zipfile.ZipInfo(MODEL, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as bundle:
        with path.open('rb') as incoming, bundle.open(info, 'w', force_zip64=True) as outgoing:
            shutil.copyfileobj(incoming, outgoing, 1024 * 1024)
    zipped = dict(name=archive.name, size=archive.stat().st_size, digest=sha(archive))
    print('compressed model {} -> {} bytes'.format(asset['size'], zipped['size']), flush=True)
    descriptor = dict(version=1, format='zip', name=archive.name, size=zipped['size'], sha256=zipped['digest'][7:],
                      unpacked=dict(name=MODEL, size=asset['size'], sha256=asset['digest'][7:]))
    descriptor_path.write_text(json.dumps(descriptor, indent=2), encoding='utf-8')
    try:
        upload('Common', archive, zipped, max_time=1200)
        upload('Common', descriptor_path, dict(name=descriptor_path.name, size=descriptor_path.stat().st_size,
                                             digest=sha(descriptor_path)))
    except Exception:
        cleanup_model({archive.name, descriptor_path.name} - before)
        raise
    return dict(transport='zip', url=public_url('Common', archive.name), size=asset['size'], sha256=asset['digest'][7:],
                archive_size=zipped['size'], archive_sha256=zipped['digest'][7:])


def try_parts(path, asset, directory):
    parts = []
    before = {a['name'] for a in attachments(release('Common'))}
    with path.open('rb') as incoming:
        index = 1
        while True:
            block = incoming.read(PART_BYTES)
            if not block:
                break
            part = Path(directory) / '{}.part{:04d}'.format(MODEL, index)
            part.write_bytes(block)
            parts.append(dict(name=part.name, size=len(block), sha256=hashlib.sha256(block).hexdigest()))
            index += 1
    manifest = dict(version=1, name=MODEL, size=asset['size'], sha256=asset['digest'][7:], parts=parts)
    manifest_path = Path(directory) / (MODEL + '.parts.json')
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    try:
        def publish(part):
            metadata = dict(name=part['name'], size=part['size'], digest='sha256:' + part['sha256'])
            return upload('Common', Path(directory) / part['name'], metadata, max_time=2700)
        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(publish, parts))
        upload('Common', manifest_path, dict(name=manifest_path.name, size=manifest_path.stat().st_size, digest=sha(manifest_path)))
    except Exception:
        cleanup_model(({p['name'] for p in parts} | {manifest_path.name}) - before)
        raise
    return dict(transport='parts', url=public_url('Common', MODEL), size=asset['size'],
                sha256=asset['digest'][7:], part_bytes=PART_BYTES)


def prepare_model(preferred='auto'):
    source = gh('/releases/tags/Common')
    original = next(a for a in source['assets'] if a['name'] == MODEL)
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', original.get('digest') or ''):
        raise ValueError('Unverified GitHub model original')
    fallback = dict(transport='github', size=original['size'], sha256=original['digest'][7:])
    if preferred == 'github':
        return dict(status='passed', model=fallback, attempts=[])
    attempts = []
    choices = ('lfs', 'zip', 'parts') if preferred == 'auto' else (preferred,)
    with tempfile.TemporaryDirectory(prefix='rmt-model-', dir=os.environ.get('RUNNER_TEMP')) as directory:
        path, asset = download('Common', original, directory)
        for choice in choices:
            try:
                if choice == 'lfs':
                    policy = try_lfs(path, asset, directory)
                else:
                    ensure_release(source)
                    policy = (try_zip if choice == 'zip' else try_parts)(path, asset, directory)
                return dict(status='passed', model=policy, attempts=attempts)
            except Exception as exc:
                attempt = dict(transport=choice, error=type(exc).__name__)
                if isinstance(exc, ValueError):
                    attempt['detail'] = str(exc)
                if isinstance(exc, HTTPError):
                    attempt['http_status'] = exc.code
                attempts.append(attempt)
                print('Model transport unavailable: ' + json.dumps(attempt), flush=True)
                if preferred != 'auto':
                    raise
    return dict(status='passed', model=fallback, attempts=attempts)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('model', 'sync', 'metadata', 'sponsor-cleanup'))
    parser.add_argument('--repo', choices=('RMT', 'RMTAssets'), default='RMTAssets')
    parser.add_argument('--tag', default='')
    parser.add_argument('--tags', default='')
    parser.add_argument('--asset-name', default='')
    parser.add_argument('--workers', type=int, default=4, choices=range(1, 7))
    parser.add_argument('--output', default='')
    parser.add_argument('--model-mode', choices=('configured', 'auto', 'lfs', 'zip', 'parts', 'github'), default='configured')
    args = parser.parse_args()
    REPO = args.repo
    SOURCE = 'https://api.github.com/repos/zclucas/' + REPO
    TARGET = 'https://api.gitcode.com/api/v5/repos/ruomengtu/' + REPO
    REMOTE = 'https://gitcode.com/ruomengtu/' + REPO + '.git'
    PUBLIC = 'https://gitcode.com/ruomengtu/' + REPO + '/releases/download/'
    if REPO != 'RMTAssets' and args.mode not in ('sync', 'metadata'):
        parser.error('Model operations apply only to RMTAssets')
    result = {}
    try:
        if args.mode == 'sponsor-cleanup':
            result = retire_sponsor_logo()
        elif args.mode == 'model':
            choice = args.model_mode
            if choice == 'configured':
                policy = Path(__file__).resolve().parents[2] / 'Scripts/AssetDownloadPolicy.json'
                choice = json.loads(policy.read_text(encoding='utf-8-sig'))['model']['transport']
                if choice not in ('lfs', 'zip', 'parts', 'github'):
                    raise ValueError('Invalid configured model transport')
            result = prepare_model(choice)
        elif args.mode == 'metadata':
            result = sync_metadata()
        else:
            tags = json.loads(args.tags) if args.tags else [args.tag] if args.tag else None
            result = dict(status='passed', assets=sync(tags, args.asset_name, args.workers), metadata=sync_metadata())
    except Exception as exc:
        result = dict(status='failed', mode=args.mode, error=type(exc).__name__)
        if isinstance(exc, HTTPError):
            result['http_status'] = exc.code
            result['host'] = urlsplit(exc.url).netloc
            result['path'] = urlsplit(exc.url).path
        print(json.dumps(result), flush=True)
    output = Path(args.output or str(Path(os.environ.get('RUNNER_TEMP', 'Test/output')) / ('gitcode-' + args.mode + '.json')))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=True), flush=True)
    raise SystemExit(0 if result.get('status') == 'passed' else 1)
