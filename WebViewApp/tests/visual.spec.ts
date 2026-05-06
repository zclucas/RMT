import { expect, type Page, test } from "@playwright/test";
import { uiCopy } from "../src/copy";
import type { RmtState } from "../src/types";
import {
  darkMacroState,
  denseMacroState,
  settingsVisualState,
  thanksVisualState,
  toolVisualState,
  visualState
} from "./fixtures/rmt-state";

const macroScenarios = [
  { name: "default-1070x590", width: 1070, height: 590, state: visualState, expectedRows: 3 },
  { name: "wide-1360x720", width: 1360, height: 720, state: visualState, expectedRows: 3 },
  { name: "dense-narrow-900x590", width: 900, height: 590, state: denseMacroState, expectedRows: 5 },
  { name: "dark-1070x590", width: 1070, height: 590, state: darkMacroState, expectedRows: 5 }
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

async function expectDarkControlsReadable(page: Page) {
  const contrastMetrics = await page.evaluate(() => {
    function channelToLinear(channel: number) {
      const srgb = channel / 255;
      return srgb <= 0.03928 ? srgb / 12.92 : ((srgb + 0.055) / 1.055) ** 2.4;
    }

    function parseRgb(value: string): [number, number, number, number] {
      const match = value.match(/rgba?\(([^)]+)\)/);
      if (!match) {
        return [0, 0, 0, 1];
      }
      const parts = match[1].split(",").map((part) => Number(part.trim()));
      return [parts[0] ?? 0, parts[1] ?? 0, parts[2] ?? 0, parts[3] ?? 1];
    }

    function luminance(rgb: [number, number, number]) {
      const [red, green, blue] = rgb.map(channelToLinear);
      return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    }

    function contrast(foreground: [number, number, number], background: [number, number, number]) {
      const fg = luminance(foreground);
      const bg = luminance(background);
      return (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
    }

    function blend(
      foreground: [number, number, number, number],
      background: [number, number, number]
    ): [number, number, number] {
      const [red, green, blue, alpha] = foreground;
      return [
        red * alpha + background[0] * (1 - alpha),
        green * alpha + background[1] * (1 - alpha),
        blue * alpha + background[2] * (1 - alpha)
      ];
    }

    function effectiveBackground(element: Element | null): [number, number, number] {
      let node: Element | null = element;
      while (node) {
        const [red, green, blue, alpha] = parseRgb(getComputedStyle(node).backgroundColor);
        if (alpha >= 1) {
          return [red, green, blue] as [number, number, number];
        }
        if (alpha > 0) {
          return blend([red, green, blue, alpha], effectiveBackground(node.parentElement));
        }
        node = node.parentElement;
      }
      return [18, 20, 23] as [number, number, number];
    }

    return Array.from(
      document.querySelectorAll<HTMLElement>(
        ".module-macro-row input:not([type='checkbox']), .module-macro-row select, .module-macro-row button, .row-disabled, .module-disabled"
      )
    ).map((element) => {
      const [red, green, blue] = parseRgb(getComputedStyle(element).color);
      return {
        text: element.textContent?.trim() || element.getAttribute("value") || element.tagName,
        ratio: contrast([red, green, blue], effectiveBackground(element))
      };
    });
  });

  expect(contrastMetrics.length).toBeGreaterThan(0);
  for (const metric of contrastMetrics) {
    expect(metric.ratio, `${metric.text} contrast`).toBeGreaterThanOrEqual(4.5);
  }
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
        await expect(page.locator(".module-collapsed-note")).toHaveCount(0);
      }

      if (scenario.name.includes("dark")) {
        await expectDarkControlsReadable(page);
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

    await expect(page.locator(".tool-legacy-page")).toBeVisible();
    await expect(page.locator(".tool-output")).toContainText("OCR 第 1 行");
    await expectShellFits(page);

    await expect(page).toHaveScreenshot("tool-active-1070x590.png", {
      animations: "disabled",
      maxDiffPixelRatio: 0.02
    });
  });

  test("keeps the settings panel stable without diagnostics", async ({ page }) => {
    await loadState(page, settingsVisualState);

    await expect(page.locator(".diagnostics-block")).toHaveCount(0);
    await expect(page.locator(".settings-legacy-page select")).toHaveCount(4);
    await expect(page.locator(".settings-legacy-page input[type='checkbox']")).toHaveCount(10);
    await expectShellFits(page);

    await expect(page).toHaveScreenshot("settings-1070x590.png", {
      animations: "disabled",
      maxDiffPixelRatio: 0.02
    });
  });
});

test.describe("thanks view", () => {
  test.use({ viewport: { width: 1070, height: 590 } });

  test("shows the T8numen contributor note with handbook effects", async ({ page }) => {
    await loadState(page, thanksVisualState);

    const contributor = page.getByRole("button", { name: "T8numen" });
    await expect(contributor).toBeVisible();
    await expect(page.locator("#t8numen-contributor-note")).toBeHidden();

    const buttonEffectBeforeHover = await contributor.evaluate((element) => ({
      beforeOpacity: window.getComputedStyle(element, "::before").opacity,
      iconWidth: window.getComputedStyle(element.querySelector(".t8numen-toc-icon")!).width
    }));

    expect(buttonEffectBeforeHover.beforeOpacity).toBe("0");
    expect(buttonEffectBeforeHover.iconWidth).toBe("0px");

    await contributor.hover();
    await page.waitForTimeout(1800);

    const buttonEffectBeforeDelay = await contributor.evaluate((element) => ({
      beforeOpacity: window.getComputedStyle(element, "::before").opacity,
      iconWidth: window.getComputedStyle(element.querySelector(".t8numen-toc-icon")!).width
    }));

    expect(buttonEffectBeforeDelay.beforeOpacity).toBe("0");
    expect(buttonEffectBeforeDelay.iconWidth).toBe("0px");
    await expect(page.locator("#t8numen-contributor-note")).toBeHidden();

    await page.waitForTimeout(1500);

    const buttonEffectAfterDelay = await contributor.evaluate((element) => ({
      beforeOpacity: window.getComputedStyle(element, "::before").opacity,
      iconWidth: parseFloat(window.getComputedStyle(element.querySelector(".t8numen-toc-icon")!).width)
    }));

    expect(Number(buttonEffectAfterDelay.beforeOpacity)).toBeGreaterThan(0.8);
    expect(buttonEffectAfterDelay.iconWidth).toBeGreaterThan(14);
    await expect(page.locator("#t8numen-contributor-note")).toBeHidden();

    await page.waitForTimeout(1900);

    const popover = page.locator("#t8numen-contributor-note");
    await expect(popover).toBeVisible();
    await expect(popover).toContainText("2.0版本的webview修改请求");
    await expect(contributor.locator(".t8numen-toc-letter")).toHaveCount(14);

    const popoverStyle = await popover.evaluate((element) => {
      const style = window.getComputedStyle(element);
      return {
        animationName: style.animationName,
        backgroundImage: style.backgroundImage
      };
    });

    expect(popoverStyle.animationName).toBe("t8numen-chapter-slide");
    expect(popoverStyle.backgroundImage).toContain("linear-gradient");
    await expectShellFits(page);
  });
});
