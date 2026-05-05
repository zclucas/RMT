import { expect, type Page, test } from "@playwright/test";
import { uiCopy } from "../src/copy";
import type { RmtState } from "../src/types";
import { denseMacroState, settingsVisualState, toolVisualState, visualState } from "./fixtures/rmt-state";

const macroScenarios = [
  { name: "default-1070x590", width: 1070, height: 590, state: visualState, expectedRows: 3 },
  { name: "wide-1360x720", width: 1360, height: 720, state: visualState, expectedRows: 3 },
  { name: "dense-narrow-900x590", width: 900, height: 590, state: denseMacroState, expectedRows: 5 }
];

async function loadState(page: Page, state: RmtState) {
  await page.addInitScript((initialState) => {
    let currentState = initialState;
    const bridgeWindow = window as Window & {
      ahk?: {
        RmtAction?: (json: string) => Promise<string>;
      };
    };

    bridgeWindow.ahk = {
      RmtAction: async (json: string) => {
        const action = JSON.parse(json) as { type: string; payload?: { tabIndex?: number } };
        if (action.type === "setTab" && action.payload?.tabIndex) {
          currentState = { ...currentState, activeTabIndex: action.payload.tabIndex };
        }

        return JSON.stringify({
          ok: true,
          message: "",
          state: currentState
        });
      }
    };
  }, state);

  await page.goto("/");
  await expect(page.locator(".classic-app")).toBeVisible();
}

async function expectShellFits(page: Page) {
  const metrics = await page.evaluate(() => {
    const doc = document.documentElement;
    const body = document.body;
    const shell = document.querySelector<HTMLElement>(".classic-app");
    const sidebar = document.querySelector<HTMLElement>(".classic-global-sidebar");
    const main = document.querySelector<HTMLElement>(".classic-main");

    return {
      docScrollWidth: Math.max(doc.scrollWidth, body.scrollWidth),
      mainRight: main?.getBoundingClientRect().right ?? 0,
      shellRight: shell?.getBoundingClientRect().right ?? 0,
      sidebarClientHeight: sidebar?.clientHeight ?? 0,
      sidebarScrollHeight: sidebar?.scrollHeight ?? 0,
      viewportWidth: window.innerWidth
    };
  });

  expect(metrics.docScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
  expect(metrics.shellRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
  expect(metrics.mainRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
  expect(metrics.sidebarScrollHeight).toBeLessThanOrEqual(metrics.sidebarClientHeight + 1);
}

for (const scenario of macroScenarios) {
  test.describe(`macro layout ${scenario.name}`, () => {
    test.use({ viewport: { width: scenario.width, height: scenario.height } });

    test("keeps the WebView shell scaled without unwanted scrollbars", async ({ page }) => {
      await loadState(page, scenario.state);
      await expect(page.locator(".module-macro-row")).toHaveCount(scenario.expectedRows);

      const metrics = await page.evaluate(() => {
        const operationCells = Array.from(
          document.querySelectorAll<HTMLElement>(".module-macro-header span:last-child, .module-macro-row .danger")
        );
        const disabledCells = Array.from(document.querySelectorAll<HTMLElement>(".row-disabled")).map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            clientWidth: element.clientWidth,
            height: rect.height,
            scrollWidth: element.scrollWidth,
            text: element.textContent?.trim() ?? ""
          };
        });
        const disabledModules = Array.from(document.querySelectorAll<HTMLElement>(".macro-module-section.is-disabled"));

        return {
          disabledModuleCount: disabledModules.length,
          operationRight: Math.max(...operationCells.map((element) => element.getBoundingClientRect().right)),
          viewportWidth: window.innerWidth,
          disabledCells
        };
      });

      await expectShellFits(page);
      expect(metrics.operationRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
      expect(metrics.disabledCells.length).toBeGreaterThan(0);

      for (const cell of metrics.disabledCells) {
        expect(cell.text).toContain(uiCopy.macro.disabled);
        expect(cell.scrollWidth).toBeLessThanOrEqual(cell.clientWidth + 1);
        expect(cell.height).toBeLessThanOrEqual(42);
      }

      if (scenario.name.includes("dense")) {
        expect(metrics.disabledModuleCount).toBe(1);
        await expect(page.locator(".module-collapsed-note")).toBeVisible();
      }

      await expect(page).toHaveScreenshot(`macro-${scenario.name}.png`, {
        animations: "disabled",
        maxDiffPixelRatio: 0.02
      });
    });
  });
}

test.describe("tool and settings views", () => {
  test.use({ viewport: { width: 1070, height: 590 } });

  test("keeps the tool panel stable with active detector and recorder output", async ({ page }) => {
    await loadState(page, toolVisualState);

    await expect(page.locator(".tool-layout")).toBeVisible();
    await expect(page.locator(".tool-output")).toContainText("OCR 第 1 行");
    await expectShellFits(page);

    await expect(page).toHaveScreenshot("tool-active-1070x590.png", {
      animations: "disabled",
      maxDiffPixelRatio: 0.02
    });
  });

  test("keeps the settings panel stable with populated diagnostics", async ({ page }) => {
    await loadState(page, settingsVisualState);

    await expect(page.locator(".diagnostics-block")).toBeVisible();
    await expect(page.locator(".panel-grid select")).toHaveCount(4);
    await expect(page.locator(".panel-grid input[type='checkbox']")).toHaveCount(6);
    await expectShellFits(page);

    await expect(page).toHaveScreenshot("settings-1070x590.png", {
      animations: "disabled",
      maxDiffPixelRatio: 0.02
    });
  });
});
