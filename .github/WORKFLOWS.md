# GitHub Actions 工作流

- `pr-check.yml`（PR 检查）：PR 与 Dev 推送时编译并检查源码编码。
- `release.yml`（版本发布）：版本标签触发打包和本仓库发布，成功后在同一工作流内调用 GitCode 任务发布两站资源。
- `sync-gitcode.yml`（GitCode 同步与资源管理）：集中自动镜像、手动维护和版本发布调用的资源上传。

版本发布仅由版本标签触发。资源上传依赖本次打包成功，只读取同次运行的产物；已删除独立资源上传工作流及按历史 run 手动补传功能。
GitCode 工作流的 `publish` 模式仅供版本发布内部调用，不在手动操作列表中。

## 资源维护操作

默认 `plan-presentation` 只预览重建计划，不修改远端资源。一次只能选择一种操作。

- `mirror`：同步代码、分支、标签及本仓库发行附件。
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
资源维护与发布资源共用并发组，避免同时改写资源；代码镜像使用独立并发组。历史迁移模式仍保留，不会自动执行。

## 已整合的入口

`backfill-assets.yml`、`update-shared-resource.yml` 的维护操作统一放入 `sync-gitcode.yml`。
`upload-assets.yml` 已并入版本发布，其资源任务调用统一 GitCode 工作流，移除手动补传。
`sync-gitcode-assets.yml` 无调用方，已移除。
`package.yml`、`verify.yml`、`webview-verify.yml` 已由现有编译检查及版本发布替代。
