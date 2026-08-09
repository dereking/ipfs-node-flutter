#!/usr/bin/env bash
set -euo pipefail

package_dir="$(cd "$(dirname "$0")/.." && pwd)"
chrome_bin="${CHROME_EXECUTABLE:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
playwright_node_path="${PLAYWRIGHT_NODE_PATH:-}"
port="${HELIA_BROWSER_TEST_PORT:-43128}"
tmp_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$package_dir" \
  >"$tmp_dir/http.log" 2>&1 &
server_pid="$!"

server_ready=""
for _ in {1..30}; do
  if curl -fsS "http://127.0.0.1:$port/web/helia_adapter.js" >/dev/null 2>&1; then
    server_ready=1
    break
  fi
  sleep 1
done

if [[ -z "$server_ready" ]]; then
  cat "$tmp_dir/http.log" >&2
  exit 1
fi

if [[ ! -x "$chrome_bin" ]]; then
  echo "Chrome executable not found: $chrome_bin" >&2
  exit 1
fi

if [[ -z "$playwright_node_path" ]]; then
  echo 'Set PLAYWRIGHT_NODE_PATH to the directory containing the playwright package.' >&2
  exit 1
fi

HELIA_BROWSER_TEST_URL="http://127.0.0.1:$port/test/browser/helia_adapter_test.html" \
CHROME_EXECUTABLE="$chrome_bin" \
PLAYWRIGHT_NODE_PATH="$playwright_node_path" \
node <<'NODE'
const { chromium } = require(`${process.env.PLAYWRIGHT_NODE_PATH}/playwright`)

const expected = 'PASS: Helia browser integration'

async function verify () {
  const browser = await chromium.launch({
    headless: true,
    executablePath: process.env.CHROME_EXECUTABLE,
    args: ['--disable-gpu', '--no-first-run'],
  })

  try {
    const page = await browser.newPage()
    const pageErrors = []
    page.on('pageerror', (error) => pageErrors.push(error.message))

    await page.goto(process.env.HELIA_BROWSER_TEST_URL, {
      waitUntil: 'domcontentloaded',
    })
    await page.waitForFunction(
      () => document.title.startsWith('PASS:') || document.title.startsWith('FAIL:'),
      undefined,
      { timeout: 30000 },
    )

    const title = await page.title()
    const body = await page.locator('body').innerText()
    if (title !== expected || body !== expected) {
      const errors = pageErrors.length === 0 ? '' : `; page errors: ${pageErrors.join(' | ')}`
      throw new Error(`Helia browser integration failed: title=${JSON.stringify(title)}, body=${JSON.stringify(body)}${errors}`)
    }

    console.log(title)
  } finally {
    await browser.close()
  }
}

verify().catch((error) => {
  console.error(error.stack || error)
  process.exitCode = 1
})
NODE
