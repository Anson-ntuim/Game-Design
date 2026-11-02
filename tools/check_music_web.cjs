// Run after Web export + HTTP server on port 8765.
// PLAYWRIGHT_MODULE=/path/to/playwright node tools/check_music_web.cjs
const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const path=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--enable-unsafe-swiftshader']});
 try {
  const page=await browser.newPage({viewport:{width:1280,height:720}});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error') errors.push(m.text());});
  await page.route('**/music-embed-test',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><body style="margin:0"><iframe src="/index.html" style="width:1280px;height:720px;border:0" sandbox="allow-scripts allow-same-origin allow-downloads" allow="autoplay; fullscreen"></iframe>'}));
  await page.goto('http://localhost:8765/music-embed-test');
  let frame;
  async function openSettings(){
   await page.waitForTimeout(7000);
   frame=page.frames().find(f=>f.url().endsWith('/index.html'));
   await frame.waitForSelector('#canvas');
   await page.mouse.click(640,350);
   await page.keyboard.press("m");
   await page.waitForTimeout(500);
   await page.screenshot({path:"build/music_tests/web-open.png"});
  }
  async function choose(name){
   const chooser=page.waitForEvent('filechooser',{timeout:10000});
   await page.mouse.click(85,115);
   await(await chooser).setFiles(path.resolve('build/music_tests',name));
  }
  async function statusContains(text){
   await frame.waitForFunction(text=>document.querySelector('#jump-music-status')?.textContent.includes(text),text,{timeout:30000});
   return frame.locator('#jump-music-status').textContent();
  }
  await openSettings();
  await choose('invalid.mp3');
  await statusContains('無法讀取音訊');
  await choose('beat_150.wav');
  assert.match(await statusContains('音樂分析完成'),/150\.0 BPM/);
  // Preview and four taps exercise the real input path.
  await page.mouse.click(65,552);
  for(let i=0;i<4;i++){await page.waitForTimeout(340);await page.keyboard.down('Space');await page.waitForTimeout(60);await page.keyboard.up('Space');}
  await statusContains('已對拍 4 次');
  await page.mouse.click(65,552);
  await page.mouse.click(225,284);
  await page.keyboard.press('Home');await page.keyboard.press('Shift+End');
  await page.keyboard.type('315',{delay:100});await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  await page.screenshot({path:'build/music_tests/web-before-apply.png'});
  await page.mouse.click(1180,654);
  assert.match(await statusContains('自訂音樂已套用'),/150\.0 BPM，第 1 拍 315 ms/);
  await page.screenshot({path:'build/music_tests/web-applied.png'});
  // Reload uses browser user:// storage, then opens the saved song.
  await page.waitForTimeout(2000);
  await page.reload();
  await openSettings();
  assert.match(await statusContains('音樂分析完成'),/150\.0 BPM，第 1 拍 315 ms/);
  await page.screenshot({path:'build/music_tests/web-calibration.png'});
  // Cancel returns without changing the active track.
  await page.mouse.click(1120,654);
  await page.mouse.click(110,44);
  assert.match(await statusContains('音樂分析完成'),/315 ms/);
  await page.mouse.click(176,115);
  await statusContains('已恢復內建音樂');
  assert.deepEqual(errors,[]);
  console.log('Web music: sandboxed import, invalid file, BPM, preview/taps, calibration, apply, reload, cancel, builtin restore passed.');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
