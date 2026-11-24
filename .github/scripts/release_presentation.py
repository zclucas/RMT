"""Keep resource release descriptions and tag chronology aligned on both sites."""
from datetime import datetime, timedelta
import os
import re
from urllib.error import HTTPError

import sync_gitcode_assets as mirror


def release_notes(tag, names):
    if tag == 'Common':
        intro = ('通用资源：键鼠输入、虚拟手柄、图像处理、OCR、语音识别等扩展组件，'
                 '以及提示音、语音与翻译模型、赞助 Logo。')
        usage = ('Audio.zip、Input.zip、ViGEm.zip 为共用包；带 _x64 / _x86 后缀的组件按程序架构选择。'
                 'Sponsor.zip 内为赞助 Logo 图片。')
    elif tag == 'Patch':
        intro = '环境修补：VC++、.NET、DirectX 运行库，Windows 7 系统补丁、界面字体和离线运行环境。'
        usage = '按操作系统与程序架构选择所需修补文件；无须重复下载已安装的运行环境。'
    else:
        match = re.fullmatch(r'v(.+)_(x64|x86)', tag)
        version, arch = match.groups() if match else (tag, '')
        intro = ('RMT {} {} 版本资源：语言包、界面图标、主程序配套组件和界面引擎。'
                 .format(version, arch))
        if version.startswith('1.2'):
            intro = 'RMT {} {} 历史版本资源，包含该版本使用的组件、语言、图标与提示音。'.format(version, arch)
        usage = '此标签中的同名文件优先使用；resources.json 列出本版本所需资源及其位置。'
    lines = [intro, '', usage, '',
             '资源内容调整时，会将旧文件保留到需要它的版本标签，保障旧版本继续下载。', '',
             '资源清单：resources.json，包含文件用途、大小、SHA-256 和压缩包内文件列表。', '',
             '附件：']
    lines.extend('- `' + name + '`' for name in sorted(names, key=str.casefold))
    return '\n'.join(lines) + '\n'


def align_tag_dates(store, wanted):
    """Annotated tags keep original commits and trees, changing only display dates."""
    releases = {r['tag_name']: r for r in store.releases()}
    # Keep Common/Patch below every version, with Common immediately above Patch.
    earliest = min(datetime.fromisoformat(r['created_at'].replace('Z', '+00:00'))
                   for tag, r in releases.items() if tag not in ('Common', 'Patch'))
    desired = {}
    for tag in wanted:
        desired[tag] = (earliest - timedelta(days=1 if tag == 'Common' else 2)
                        if tag in ('Common', 'Patch') else
                        datetime.fromisoformat(releases[tag]['created_at'].replace('Z', '+00:00')))
    # Distinguish tags sharing a commit timestamp, preserving the requested order.
    for index in range(len(wanted)-2, -1, -1):
        tag, after = wanted[index:index+2]
        if desired[tag] <= desired[after]:
            desired[tag] = desired[after] + timedelta(seconds=1)
    for tag in ('Common', 'Patch'):
        ref = mirror.gh('/git/ref/tags/' + tag)['object']
        commit = ref['sha']
        if ref['type'] == 'tag':
            annotated = mirror.gh('/git/tags/' + commit)
            if annotated['tagger']['date'] == desired[tag].isoformat().replace('+00:00', 'Z'):
                continue
            commit = annotated['object']['sha']
        obj = mirror.gh('/git/tags', data=dict(tag=tag, message='RMT ' + tag + ' resources',
            object=commit, type='commit', tagger=dict(name='RMT resources',
            email='resources@users.noreply.github.com',
            date=desired[tag].isoformat().replace('+00:00', 'Z'))))
        mirror.gh('/git/refs/tags/' + tag, data=dict(sha=obj['sha'], force=True), method='PATCH')
    # GitCode maintains a separate Git history (including its LFS model). Preserve
    # each original commit there too, and assign matching annotated-tag dates.
    checkout = store.directory / 'presentation-tags'
    mirror.git('init', '--bare', str(checkout))
    mirror.git('fetch', '--quiet', '--depth=1', mirror.REMOTE,
               '+refs/tags/*:refs/tags/*', cwd=checkout)
    for tag in reversed(wanted):
        old = mirror.git('rev-parse', 'refs/tags/' + tag, cwd=checkout).strip()
        commit = mirror.git('rev-parse', 'refs/tags/' + tag + '^{}', cwd=checkout).strip()
        timestamp = str(int(desired[tag].timestamp()))
        raw = ('object ' + commit + '\ntype commit\ntag ' + tag +
               '\ntagger RMT resources <resources@users.noreply.github.com> ' + timestamp +
               ' +0000\n\nRMT ' + tag + ' resources; presentation order v2\n')
        path = store.directory / 'presentation-tag.txt'
        path.write_text(raw, encoding='utf-8')
        obj = mirror.git('hash-object', '-t', 'tag', '-w', str(path), cwd=checkout).strip()
        if obj != old:
            mirror.git('push', '--quiet', '--force-with-lease=refs/tags/' + tag + ':' + old,
                       mirror.REMOTE, obj + ':refs/tags/' + tag, cwd=checkout)
    return {tag: date.isoformat().replace('+00:00', 'Z') for tag, date in desired.items()}


def organize_releases(store):
    current = store.releases()
    wanted = [r['tag_name'] for r in current if r['tag_name'] not in ('Common', 'Patch')]
    wanted += ['Common', 'Patch']
    dates = align_tag_dates(store, wanted)
    refresh_descriptions(store, wanted)
    if [r['tag_name'] for r in store.releases()] != wanted:
        # Republish metadata with the canonical tag dates. Assets stay attached.
        for tag in ('Common', 'Patch'):
            source = store.source(tag)
            try:
                mirror.gh('/releases/' + str(source['id']), data=dict(draft=True), method='PATCH')
            finally:
                mirror.gh('/releases/' + str(source['id']),
                          data=dict(draft=False, make_latest='false'), method='PATCH')
    github_order = [r['tag_name'] for r in store.releases()]
    gitcode_order = [r['tag_name'] for r in mirror.pages(mirror.gc, '/releases?direction=desc')]
    tags = mirror.pages(mirror.gc, '/tags')
    probe = None
    if gitcode_order != wanted:
        probe = probe_metadata_retention(store)
        if probe:
            # Recreate metadata only if a disposable release proved that this
            # deployment retains attachment IDs and contents across the operation.
            for tag in reversed(wanted):
                before = mirror.release(tag)
                identity = lambda r: sorted((a['id'], a['name'], a['size'], a.get('digest'))
                                             for a in mirror.attachments(r))
                mirror.gc('/releases/' + tag, method='DELETE')
                restored = mirror.ensure_release(store.source(tag))
                if identity(restored) != identity(before):
                    raise ValueError('Release metadata recreation did not retain attachments: ' + tag)
            gitcode_order = [r['tag_name'] for r in mirror.pages(mirror.gc, '/releases?direction=desc')]
    return dict(expected_order=wanted, github_order=github_order, gitcode_order=gitcode_order,
                gitcode_tag_order=[t['name'] for t in tags],
                metadata_retains_assets=probe,
                order_matches=github_order == gitcode_order == wanted)


def probe_metadata_retention(store):
    """Never experiment on a real release or remove its only attachment copy."""
    tag = 'rmt-order-probe-' + os.environ['GITHUB_RUN_ID']
    options = dict(tag_name=tag, target_commitish='main', name=tag,
                   body='Temporary CI metadata retention probe', release_status='pre')
    path = store.directory / 'order-probe.json'
    path.write_text('{"test":"metadata-retention"}\n', encoding='utf-8')
    expected = dict(name=path.name, size=path.stat().st_size, digest=mirror.sha(path))
    try:
        mirror.gc('/releases', data=options)
        mirror.upload(tag, path, expected, max_time=600)
        before = mirror.attachments(mirror.release(tag))
        mirror.gc('/releases/' + tag, method='DELETE')
        after = mirror.gc('/releases', data=options)
        if [(a['id'], a['name'], a['size']) for a in mirror.attachments(after)] != [
                (a['id'], a['name'], a['size']) for a in before]:
            return False
        mirror.readback(tag, expected)
        return True
    finally:
        if mirror.release(tag):
            mirror.gc('/releases/' + tag, method='DELETE')
        mirror.git('push', '--quiet', mirror.REMOTE, ':refs/tags/' + tag,
                   cwd=store.directory / 'presentation-tags')


def refresh_descriptions(store, tags=None):
    for tag in tags or [r['tag_name'] for r in store.releases()]:
        source = store.source(tag)
        body = release_notes(tag, [a['name'] for a in store.assets(tag)])
        if source.get('name') != tag or source.get('body') != body:
            mirror.gh('/releases/' + str(source['id']),
                      data=dict(name=tag, body=body, make_latest='false'), method='PATCH')
        mirror.ensure_release(store.source(tag))
