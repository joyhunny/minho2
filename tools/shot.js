// 배포된 minho2: 로딩 → 인트로 → 난이도 카드 탭 → 다음 화면까지 찍어 검증.
const { chromium } = require('playwright');
const path = require('path');
const URL = 'https://joyhunny.github.io/minho2/';
const OUT = __dirname;

(async () => {
  const browser = await chromium.launch({ channel: 'chrome' });
  const ctx = await browser.newContext({
    viewport: { width: 720, height: 1280 }, deviceScaleFactor: 2,
    isMobile: true, hasTouch: true,
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => console.log('PAGEERR', e.message));
  await page.goto(URL, { waitUntil: 'load', timeout: 60000 });
  await page.waitForTimeout(16000);
  await page.screenshot({ path: path.join(OUT, 'port-1-diff.png') });
  console.log('shot1 done');
  await page.mouse.click(360, 640);
  await page.waitForTimeout(1500);
  await page.screenshot({ path: path.join(OUT, 'port-2-diff.png') });
  console.log('shot2 done');
  await page.mouse.click(237, 213);
  await page.waitForTimeout(3500);
  await page.screenshot({ path: path.join(OUT, 'port-3-after.png') });
  console.log('shot3 done');
  await page.mouse.click(360, 640);
  await page.waitForTimeout(3000);
  await page.screenshot({ path: path.join(OUT, 'port-4-game.png') });
  console.log('shot4 done');
  await browser.close();
  console.log('DONE');
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
