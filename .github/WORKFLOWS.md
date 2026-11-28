# GitHub Actions 工作流

## 编译校验（pr-check.yml）

PR 创建或更新、Dev 分支推送时执行编译与源码编码检查。不打包发行、不发布附件。

## Github资源管理（release.yml）

GitHub 的发行版、资源附件、清单和资源标签均由此入口管理。

- 版本标签 `v*` 推送：校验版本号、语言包和更新日志，双架构打包，发布本仓库 Release 与附件，再发布 RMTAssets 分层资源。
- 手动运行：默认 `inspect` 只查看 GitHub 发行列表；可选择共享资源更新、清单补齐、发行说明与标签排序整理、历史资源迁移、恢复或废弃资源清理。
- GitHub 写操作使用 `RMT_RESOURCE_PROVIDER=github`，不直接修改 GitCode。
- 发布或维护成功后调用 `GitCode同步`，读取已完成的 GitHub 资源并同步到 GitCode。
- 已删除按历史 run 手动补传；版本发布仅消费本次打包产物，校验标签及提交一致性。

手动维护模式：`shared-url`、`complete-catalogs`、`presentation`、`normalize`、`catalog-names`、`retire-obsolete`、`restore-stable`、`migrate`、`sponsor-cleanup`。既有版本依赖与正式版附件保护规则保持有效。

## GitCode同步（sync-gitcode.yml）

全部 GitCode 写操作集中到此工作流，GitHub 令牌只读。

- 分支/标签推送、创建、删除及每日北京时间 12:17：镜像 GitHub 的分支和标签。
- 标签推送或 GitHub Release 发布、编辑：额外同步本仓库发行版及附件。
- Github资源管理成功后的内部调用 `mirror-all`：同步代码、本仓库发行附件以及 RMTAssets 资源附件与清单。
- 手动 `mirror`：同步两仓库；`sync`：仅同步资源，可按标签或附件过滤。
- 手动默认 `plan-presentation`：只预览 GitCode 发行顺序；`rebuild-presentation`：按校验备份重建 GitCode 发行顺序。

两个管理入口共用资源写入并发组，顺序执行，避免一边发布一边读取未完成资源。
历史维护能力已经迁入相应平台入口，不再保留独立资源上传、资源维护工作流。
