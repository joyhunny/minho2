// 진짜 크롬(터치)으로 로컬 빌드를 띄워 이동·공격·패널을 검증한다 (실기기 대용 스모크 테스트).
// CSS px(360x640) = 게임 캔버스(720x1280)의 절반. 탭 좌표는 CSS px.
//
// 실행 (WSL):
//   1) 빌드:  GODOT=~/godot/Godot_v4.3-stable_linux.x86_64 bash tools/deploy.sh  (또는 --export 만)
//   2) 서버:  (cd build && python3 -m http.server 8099 &)
//   3) 의존:  npm install playwright   (브라우저는 캐시된 chromium 1223 사용)
//      ※ 이 머신엔 크롬 시스템 .so 가 없어 ~/.local/chromedeps 에 받아둠(LD_LIBRARY_PATH 로 연결).
//         재현: cd /tmp && apt-get download libnspr4 libnss3 libasound2t64
//               && for d in *.deb; do dpkg -x $d ~/.local/chromedeps; done
//   4) 검증:  node tools/touch_verify.js '[[118,106],[180,137],[180,320]]'
//             (인자 = 난이도→지역→입장배너 탭 좌표. recon 으로 주면 메뉴 스샷만.)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');
const URL = 'http://localhost:8099/index.html';
const OUT = path.join(__dirname, 'verify');
const LIB = process.env.HOME + '/.local/chromedeps/usr/lib/x86_64-linux-gnu';
const EXE = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1223/chrome-headless-shell-linux64/chrome-headless-shell';

const STEP = process.argv[2] || 'recon';

function pngSize(p){ try { return fs.statSync(p).size; } catch(e){ return 0; } }
// 두 PNG 의 바이트 차이 비율(대략적 화면 변화 지표는 아래 픽셀 diff 로 별도 계산)
async function pixelDiff(page, a){
  // 현재 캔버스를 base64로 받아 a(이전)과 픽셀 차이 비율 계산
  const cur = await page.evaluate(() => {
    const c = document.getElementById('canvas');
    return c.toDataURL('image/png');
  });
  return cur;
}

(async () => {
  const browser = await chromium.launch({
    headless: true, executablePath: EXE,
    env: { ...process.env, LD_LIBRARY_PATH: LIB },
  });
  const ctx = await browser.newContext({
    viewport: { width: 360, height: 640 }, deviceScaleFactor: 2,
    isMobile: true, hasTouch: true,
  });
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', e => errs.push('PAGEERR '+e.message));
  page.on('console', m => { if (m.type()==='error') errs.push('CONSOLE '+m.text()); });
  await page.goto(URL, { waitUntil: 'load', timeout: 60000 });
  const client = await page.context().newCDPSession(page);
  async function touch(type, x, y){ // x,y in CSS px
    await client.send('Input.dispatchTouchEvent', {
      type, touchPoints: type==='touchEnd'?[]:[{x, y}],
    });
  }
  async function tap(x,y){ await touch('touchStart',x,y); await page.waitForTimeout(60); await touch('touchEnd',x,y); }

  await page.waitForTimeout(8000);
  await page.screenshot({ path: path.join(OUT,'tv-1-intro.png') });
  await tap(180,320);                 // 인트로 스킵
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(OUT,'tv-2-diff.png') });

  if (STEP === 'recon') {
    console.log('RECON done. errs=', JSON.stringify(errs));
    await browser.close();
    return;
  }

  // STEP=full: 인자로 받은 탭 좌표들로 난이도→지도→게임 진입 후 이동 검증
  const taps = JSON.parse(STEP); // [[x,y],...] CSS px
  for (const [x,y] of taps){ await tap(x,y); await page.waitForTimeout(2500); }
  await page.screenshot({ path: path.join(OUT,'tv-3-ingame.png') });

  const shot = async (name) => { const p = path.join(OUT,name); await page.screenshot({ path: p }); return p; };
  // 신뢰 가능한 실제 스크린샷(PNG)을 디스크에서 읽어 base64 로 브라우저에 넘겨 디코드 → 픽셀 비교.
  // region 지정 시 그 사각형 안에서만 변화율 계산(조이스틱/공격버튼 국소 변화 검출용).
  async function diffOf(fileA, fileB, region){
    const aURL = 'data:image/png;base64,' + fs.readFileSync(fileA).toString('base64');
    const bURL = 'data:image/png;base64,' + fs.readFileSync(fileB).toString('base64');
    return await page.evaluate(([a,b,reg]) => {
      function load(src){ return new Promise(r=>{ const im=new Image(); im.onload=()=>r(im); im.src=src; }); }
      return (async()=>{
        const [ia,ib] = await Promise.all([load(a),load(b)]);
        const w=ia.width,h=ia.height;
        const cv=document.createElement('canvas'); cv.width=w; cv.height=h; const cx=cv.getContext('2d');
        cx.drawImage(ia,0,0); const da=cx.getImageData(0,0,w,h).data;
        cx.drawImage(ib,0,0); const db=cx.getImageData(0,0,w,h).data;
        const x0=reg?reg[0]:0, y0=reg?reg[1]:0, x1=reg?reg[2]:w, y1=reg?reg[3]:h;
        let diff=0, tot=0;
        for(let y=y0;y<y1;y++) for(let x=x0;x<x1;x++){
          const i=(y*w+x)*4; tot++;
          if(Math.abs(da[i]-db[i])+Math.abs(da[i+1]-db[i+1])+Math.abs(da[i+2]-db[i+2])>40) diff++;
        }
        return diff/tot*100;
      })();
    }, [aURL,bURL,region||null]);
  }

  const JOY_REGION = [60,820,300,1060];   // 조이스틱 베이스(150,900) 주변 box (device px)
  const ATK_REGION = [520,1060,700,1240]; // 칼 버튼 + 플레이어 스윙 주변

  // ── (A) 베이스라인: 손 안 댄 1.2초 동안의 자연 변화(적·동료 움직임) ──
  const sPre = await shot('tv-a-pre.png');
  await page.waitForTimeout(1200);
  const sAmb = await shot('tv-b-ambient.png');
  const ambientFull = await diffOf(sPre, sAmb);
  const ambientJoy  = await diffOf(sPre, sAmb, JOY_REGION);

  // ── (B) 왼쪽을 누른 채 오른쪽으로 끌기(조이스틱) ──
  const sPreTouch = await shot('tv-c-pretouch.png');
  await touch('touchStart', 75, 450);
  await page.waitForTimeout(150);
  const sHold = await shot('tv-4-joystick-hold.png');   // 조이스틱 원이 떠야
  for (let i=0;i<14;i++){ await touch('touchMove', 75+i*5, 450); await page.waitForTimeout(80); }
  await page.waitForTimeout(300);
  const sMoved = await shot('tv-5-moved.png');
  await touch('touchEnd',0,0);
  const joyAppear = await diffOf(sPreTouch, sHold, JOY_REGION); // 누른 순간 조이스틱 영역 변화
  const moveFull  = await diffOf(sPreTouch, sMoved);            // 드래그 후 전체 변화(=이동)

  // ── (C) 공격: 우하단 칼 버튼 (탭 직후 프레임 = 스윙) ──
  const sBeforeAtk = await shot('tv-d-beforeatk.png');
  await touch('touchStart', 305, 575);
  await page.waitForTimeout(80);
  const sAtk = await shot('tv-6-attack.png');
  await touch('touchEnd', 305, 575);
  const atkChange = await diffOf(sBeforeAtk, sAtk, ATK_REGION);

  console.log('── 결과 (단위: 픽셀 변화율 %) ──');
  console.log('조이스틱 영역  | 무터치:', ambientJoy.toFixed(1), ' vs 누른순간:', joyAppear.toFixed(1), '  →', (joyAppear>ambientJoy*3&&joyAppear>3?'조이스틱 뜸 ✅':'의심 ❌'));
  console.log('전체 화면      | 무터치:', ambientFull.toFixed(1), ' vs 드래그후:', moveFull.toFixed(1), '  →', (moveFull>ambientFull*1.8?'이동함 ✅':'의심 ❌'));
  console.log('칼버튼+스윙영역| 탭 직후 변화:', atkChange.toFixed(1), '  →', (atkChange>3?'공격 반응 ✅':'의심 ❌'));
  console.log('errs =', JSON.stringify(errs));
  await browser.close();
  console.log('DONE');
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
