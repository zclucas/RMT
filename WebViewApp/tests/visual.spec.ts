import { expect, test } from "@playwright/test";
import { visualState } from "./fixtures/rmt-state";

const scenarios = [
  { name: "default-1070x590", width: 1070, height: 590 },
  { name: "wide-1360x720", width: 1360, height: 720 }
];

for (const scenario of scenarios) {
  test.describe(`macro layout ${scenario.name}`, () => {
    test.use({ viewport: { width: scenario.width, height: scenario.height } });

    test("keeps the WebView shell scaled without unwanted scrollbars", async ({ page }) => {
      await page.addInitScript((state) => {
        window.ahk = {
          RmtAction: async () =>
            JSON.stringify({
              ok: true,
              message: "",
              state
            })
        };
      }, visualState);

      await page.goto("/");
      await expect(page.locator(".classic-app")).toBeVisible();
      await expect(page.locator(".module-macro-row")).toHaveCount(3);

      const metrics = await page.evaluate(() => {
        const doc = document.documentElement;
        const body = document.body;
        const sidebar = document.querySelector<HTMLElement>(".classic-global-sidebar");
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

        return {
          docScrollWidth: Math.max(doc.scrollWidth, body.scrollWidth),
          operationRight: Math.max(...operationCells.map((element) => element.getBoundingClientRect().right)),
          sidebarClientHeight: sidebar?.clientHeight ?? 0,
          sidebarScrollHeight: sidebar?.scrollHeight ?? 0,
          viewportWidth: window.innerWidth,
          disabledCells
        };
      });

      expect(metrics.docScrollWidth).toBeLessThanOrEqual(metrics.viewportWidth + 1);
      expect(metrics.operationRight).toBeLessThanOrEqual(metrics.viewportWidth + 1);
      expect(metrics.sidebarScrollHeight).toBeLessThanOrEqual(metrics.sidebarClientHeight + 1);
      expect(metrics.disabledCells.length).toBeGreaterThan(0);

      for (const cell of metrics.disabledCells) {
        expect(cell.text).toContain("禁用");
        expect(cell.scrollWidth).toBeLessThanOrEqual(cell.clientWidth + 1);
        expect(cell.height).toBeLessThanOrEqual(42);
      }

      await expect(page).toHaveScreenshot(`macro-${scenario.name}.png`, {
        animations: "disabled",
        maxDiffPixelRatio: 0.02
      });
    });
  });
}
