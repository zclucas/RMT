#Requires AutoHotkey v2.0

; 主进程与 Worker 的共享内存 ABI。偏移均为字节；修改布局必须同时升级两端。
; 游标独占缓存行；帧按 8 字节对齐，控制位字段固定为 Int64，x86/x64 共用同一布局。
class WorkerIpcLayout {
    static ChannelCapacityBytes := 1024 * 1024
    static RingMetadataBytes := 192
    static HeadOffset := 0
    static TailOffset := 64
    static NotifyOffset := 128
    static MinimumFrameBytes := 24
    static FrameHeaderBytes := 20
    static FrameIdOffset := 4
    static FrameFlagsOffset := 8
    static FrameLengthOffset := 16
    static AlignmentBytes := 8
    static Utf16UnitBytes := 2
    static MaxChunkChars := 32768
    static CounterMask := 0xFFFFFFFF
    static WrapMarker := -1
    static ContinuationType := 0

    ; HUD 为覆盖写入的最新帧单槽，尾部句柄表不能与文本区重叠。
    static HudCapacityBytes := 64 * 1024
    static HudMetadataBytes := 64
    static HudPendingOffset := 0
    static HudSequenceOffset := 4
    static HudLengthOffset := 8
    static HudPayloadOffset := 16
    static HudMaxPayloadBytes := 65000
    static HudHandleCountOffset := 65024
    static HudHandleTableOffset := 65032
    static HudHandleEntryBytes := 16
    static HudHandleValueOffset := 8
    static HudMaxHandles := 35

    static RingMappingBytes() => this.RingMetadataBytes + this.ChannelCapacityBytes
    static HudMappingBytes() => this.HudMetadataBytes + this.HudCapacityBytes
}
