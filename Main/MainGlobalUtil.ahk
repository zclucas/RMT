#Requires AutoHotkey v2.0
; 传 Timing 表的 TableID（表身份=ID，位置不代表身份）
global MyTimingScheduler := TimingScheduler("")
; §23 网络触发监听（仅主进程；Thread\Work.ahk 不 include 本文件，Worker 不感知监听）
global MyNetworkServer := NetworkServer()