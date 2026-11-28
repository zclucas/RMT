# GitHub Actions 工作流

- `pr-check.yml`（PR 检查）：PR 与 Dev 推送时编译并检查源码编码。
- `release.yml`（版本发布）：版本标签触发双架构打包并发布本仓库附件。
- `upload-assets.yml`（资源上传）：版本发布成功后发布两站分层资源；保留按来源 run 手动补传。
- `sync-gitcode.yml`（同步 GitCode 代码与发行版）：镜像分支、标签与本仓库发行版；支持手动和定时校准。
- `backfill-assets.yml`（资源维护）：手动维护 RMTAssets / GitCode 资源。

## 资源维护操作

默认 `plan-presentation` 只预览重建计划，不修改远端资源。一次只能选择一种操作。

- `sync`：补齐 GitCode 资源，可用 `tag` 和 `asset_name` 缩小范围，留空同步全部。
- `shared-url`：更新 Common / Patch 文件，先归档旧版本依赖；必须填写分类、附件名、下载地址和 SHA-256。
- `complete-catalogs`：补齐初始资源清单缺失的离线包记录。
- `presentation`：仅整理发行说明与排序。
- `normalize`：合并共用包、清理旧附件并整理清单。
- `catalog-names`：统一资源清单名称。
- `retire-obsolete`：清理 Common、Patch 与测试版中的废弃资源，跳过正式版。
- `restore-stable`：恢复 v1.2 原始附件及清单。
- `migrate`：按版本、Common、Patch 重组历史资源位置。
- `sponsor-cleanup`：校验 Sponsor.zip 后清理单独的赞助图片。
- `rebuild-presentation`：从校验备份重建 GitCode 发行顺序；建议先运行默认预览。

同步、共享更新与赞助清理默认使用 Ubuntu；历史整理保留 macOS runner。可通过 `resource_runner` 覆盖。
资源维护与资源上传共用并发组，避免同时改写资源。历史迁移模式仍保留，以便恢复和补救，不会自动执行。

## 已移除的入口

`backfill-assets.yml` 已改为资源维护，合入 `update-shared-resource.yml`；保留原文件路径以延续维护历史记录。
`sync-gitcode-assets.yml` 没有调用方；资源上传脚本已直接发布两站资源，因此移除重复入口。
`package.yml`、`verify.yml`、`webview-verify.yml` 是旧版本遗留，已由现有编译检查及版本发布替代。
