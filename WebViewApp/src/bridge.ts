import type { RmtAction, RmtResult, RmtState } from "./types";
import { uiCopy } from "./copy";
import { fallbackState } from "./fallbackState";

declare global {
  interface Window {
    ahk?: {
      RmtAction?: (json: string) => Promise<string> | string;
      gui?: {
        Minimize?: () => void;
        Maximize?: () => void;
        Restore?: () => void;
      };
      global?: {
        WinClose?: (target: string) => void;
      };
    };
    __rmtReceiveState?: (state: RmtState) => void;
  }
}

export async function callRmt(action: RmtAction): Promise<RmtResult> {
  if (!window.ahk?.RmtAction) {
    return {
      ok: true,
      message: uiCopy.common.runningWithoutBridge,
      state: fallbackState
    };
  }

  const raw = await window.ahk.RmtAction(JSON.stringify(action));
  return JSON.parse(String(raw)) as RmtResult;
}

export function getFallbackState(): RmtState {
  return fallbackState;
}
