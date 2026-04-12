#!/usr/bin/env node
// screenshot-flow.mjs — capture screenshots of each fixture from the
// latest Flow comparison page using Playwright.

import { chromium } from 'playwright';
import { mkdir, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  // Find latest flow comparison
  const resultsDir = join(__dirname, 'results');
  const dirs = (await readdir(resultsDir)).filter(d => d.startsWith('flow-')).sort();
  const latest = dirs[dirs.length - 1];
  if (!latest) { console.error('No flow results found'); process.exit(1); }

  const htmlPath = join(resultsDir, latest, 'comparison.html');
  const outDir = join(resultsDir, latest, 'screenshots');
  await mkdir(outDir, { recursive: true });

  console.log('Source:', htmlPath);
  console.log('Output:', outDir);

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  await page.goto(`file://${htmlPath}`);
  await page.waitForTimeout(1000);

  // Screenshot the full page
  await page.screenshot({ path: join(outDir, 'full-page.png'), fullPage: true });
  console.log('✓ full-page.png');

  // Screenshot each fixture section
  const fixtures = await page.$$('.fixture');
  for (let i = 0; i < fixtures.length; i++) {
    const title = await fixtures[i].$eval('h2', el => el.textContent).catch(() => `fixture-${i}`);
    const safeName = title.replace(/[^a-zA-Z0-9_.-]/g, '_');
    await fixtures[i].screenshot({ path: join(outDir, `${safeName}.png`) });
    console.log(`✓ ${safeName}.png`);
  }

  await browser.close();
  console.log(`\nDone: ${fixtures.length} fixtures captured in ${outDir}`);
}

main().catch(e => { console.error(e); process.exit(1); });
