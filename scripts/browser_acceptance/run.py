# /// script
# requires-python = ">=3.11"
# dependencies = ["playwright"]
# ///
"""Two isolated browser contexts -> real local API -> local EVM acceptance.
Test provider delegates signing to unlocked local Hardhat accounts, never a real wallet.
Run via uv run scripts/browser_acceptance/run.py --browser <chrome-or-edge.exe>.
Requires a Flutter build with CHAIN_ID=31337, a configured API and seeded local accounts.
"""
import argparse
import json
import re
import time
import urllib.request
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit

from playwright.sync_api import sync_playwright

def rpc(url, method, params):
    request = urllib.request.Request(url, data=json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    ).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=15) as response:
        value = json.load(response)
    if "error" in value:
        raise RuntimeError("Local RPC rejected " + method)
    return value["result"]

def local_url(value):
    parsed = urlsplit(value)
    _ = parsed.port
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"localhost", "127.0.0.1"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path not in ("", "/")
    ):
        raise argparse.ArgumentTypeError("Only clean loopback HTTP origin URLs are allowed")
    return value.rstrip("/")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-url", type=local_url, default="http://127.0.0.1:18080")
    parser.add_argument("--api-url", type=local_url, default="http://127.0.0.1:18000")
    parser.add_argument("--rpc-url", type=local_url, default="http://127.0.0.1:8545")
    parser.add_argument("--browser", help="Browser executable; omit to use Playwright Chromium")
    parser.add_argument("--output-dir", type=Path, default=Path("validation-results/browser"))
    parser.add_argument("--merchant-clock-skew", type=int, default=0, help="Test browser clock offset in seconds")
    parser.add_argument("--subscriber-clock-skew", type=int, default=0, help="Test browser clock offset in seconds")
    parser.add_argument("--inject-cache-failure", action="store_true",
        help="Fail subscriber pending writes AFTER broadcast plus simulate tracking API outage")
    parser.add_argument("--test-replacement", action="store_true", help="Cancel a pending subscription and recover through the UI")
    args = parser.parse_args()
    if int(rpc(args.rpc_url, "eth_chainId", []), 16) != 31337:
        raise SystemExit("Acceptance requires local chain31337; no remote chain is used")
    accounts = rpc(args.rpc_url, "eth_accounts", [])
    args.output_dir.mkdir(parents=True, exist_ok=True)
    results, tokens = [], {}
    status = "fail"
    started = datetime.now(UTC).isoformat()
    plan_title = "Browser acceptance " + str(int(time.time()))
    browser = None

    def record(name, **evidence):
        results.append({"name": name, "status": "pass", **evidence})
        print(name + ": pass", flush=True)

    def api(path, token=None):
        request = urllib.request.Request(args.api_url + path,
            headers={"Authorization": "Bearer " + token} if token else {})
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)

    def until(check, timeout=45):
        stop = time.monotonic() + timeout
        while time.monotonic() < stop:
            result = check()
            if result:
                return result
            if browser and browser.contexts and browser.contexts[0].pages:
                browser.contexts[0].pages[0].wait_for_timeout(200)
            else:
                time.sleep(.2)
        raise TimeoutError("Acceptance condition was not observed")

    def button(page, name):
        target = page.get_by_role("button", name=name, exact=True).first
        width, height = page.viewport_size["width"], page.viewport_size["height"]

        def in_viewport():
            box = target.bounding_box(timeout=1000) if target.count() else None
            return (
                box is not None
                and 0 <= box["x"] + box["width"] / 2 < width
                and 0 <= box["y"] + box["height"] / 2 < height
            )

        # Flutter can keep an off-screen control in the semantics tree.
        if in_viewport():
            return target
        page.mouse.move(width * 0.75, height * 0.65)
        page.mouse.wheel(0, -20000)
        for _ in range(25):
            page.wait_for_timeout(100)
            if in_viewport():
                return target
            page.mouse.wheel(0, 600)
        raise RuntimeError("Button not visible in the viewport: " + name)

    def click(page, name):
        target = button(page, name)
        target.wait_for(state="visible")
        stop = time.monotonic() + 30
        while target.get_attribute("aria-disabled") == "true":
            if time.monotonic() >= stop:
                raise TimeoutError("Button remained disabled: " + name)
            page.wait_for_timeout(100)
        target.click(timeout=30000)

    def fill_field(page, label, value):
        # The connection screen has one textbox; prefix semantics can change its accessible name.
        field = page.get_by_role("textbox").first if label == "API URL" else page.get_by_role("textbox", name=label, exact=True)
        field.wait_for(state="visible")
        for _ in range(3):
            field.click()
            page.wait_for_timeout(100)
            field.press("Control+a")
            field.fill(value)
            page.wait_for_timeout(100)
            if field.input_value() == value:
                return
        raise RuntimeError("Field did not retain value: " + label)

    def form(page, values):
        for label, value in values.items():
            fill_field(page, label, value)
        click(page, "Xác nhận")

    def provider_script(account, skew):
        return """(() => {
          const account = ACCOUNT, rpcUrl = RPC;
          const listeners = new Map();
          const NativeDate = Date, skewMillis = SKEW * 1000;
          class TestDate extends NativeDate {
            constructor(...args) { super(...(args.length ? args : [NativeDate.now() + skewMillis])); }
            static now() { return NativeDate.now() + skewMillis; }
          }
          window.Date = TestDate;
          window.__testFailPendingCache = false;
          window.__testPendingWriteFailures = 0;
          const originalSetItem = Storage.prototype.setItem;
          Storage.prototype.setItem = function(key, value) {
            if (window.__testFailPendingCache && String(key).startsWith('prepaidguard.pending.')) {
              window.__testPendingWriteFailures++;
              throw new DOMException('Injected pending-cache failure', 'QuotaExceededError');
            }
            return originalSetItem.call(this, key, value);
          };
          window.__testTransactions = [];
          window.ethereum = {
            isMetaMask: true,
            on: (event, callback) => listeners.set(event, callback),
            removeListener: (event, callback) => listeners.delete(event),
            request: async ({method, params = []}) => {
              if (method === 'eth_accounts' || method === 'eth_requestAccounts') return [account];
              if (method === 'eth_sendTransaction' && params[0].from.toLowerCase() !== account.toLowerCase())
                throw new Error('Test provider refuses a different sender');
              if (method === 'wallet_switchEthereumChain') {
                if (params[0].chainId !== '0x7a69') throw new Error('Local chain only');
                return null;
              }
              if (method === 'eth_signTypedData_v4' && typeof params[1] === 'string')
                params = [params[0], JSON.parse(params[1])];
              if (method === 'eth_sendTransaction' &&
                  window.__testHoldNextVaultSend && String(params[0].to).toLowerCase() === VAULT) {
                window.__testHoldNextVaultSend = false;
                await new Promise(resolve => { window.__testReleaseVaultPrompt = resolve; });
              }
              if (method === 'eth_sendTransaction' &&
                  window.__testPauseNextVaultSend && String(params[0].to).toLowerCase() === VAULT) {
                window.__testPauseNextVaultSend = false;
                await fetch(rpcUrl, {method:'POST', headers:{'Content-Type':'application/json'},
                  body:JSON.stringify({jsonrpc:'2.0', id:1, method:'evm_setAutomine', params:[false]})});
              }
              const response = await fetch(rpcUrl, {method:'POST',
                headers:{'Content-Type':'application/json'},
                body:JSON.stringify({jsonrpc:'2.0', id:1, method, params})});
              const result = await response.json();
              if (result.error) throw new Error('Local RPC rejected ' + method);
              if (method === 'eth_sendTransaction') {
                window.__testTransactions.push(result.result);
                if (CACHEFAULT && String(params[0].to).toLowerCase() === VAULT)
                  window.__testFailPendingCache = true;
              }
              return result.result;
            }
          };
        })();""".replace("ACCOUNT", json.dumps(account)).replace("RPC", json.dumps(args.rpc_url)).replace(
            "SKEW", str(skew)).replace("CACHEFAULT",
            json.dumps(args.inject_cache_failure and account.lower() == accounts[2].lower())).replace(
            "VAULT", json.dumps(config["vault_address"].lower()))

    def attach_token(page, key):
        def response_received(response):
            if response.url.endswith("/api/v1/auth/verify") and response.status == 200:
                tokens[key] = response.json()["access_token"]
        page.on("response", response_received)

    def open_session(browser, account, key, context=None, query=""):
        if context is None:
            context = browser.new_context(viewport={"width": 1440, "height": 1100})
            skew = args.merchant_clock_skew if key == "merchant" else args.subscriber_clock_skew
            context.add_init_script(provider_script(account, skew))
        page = context.new_page()
        page.set_default_timeout(30000)
        attach_token(page, key)
        page.goto(args.app_url + "/" + query, wait_until="networkidle")
        placeholder = page.locator("flt-semantics-placeholder")
        placeholder.wait_for(state="attached", timeout=30000)
        placeholder.dispatch_event("click")
        button(page, "Kết nối ví / Đăng nhập").wait_for(state="visible")
        if page.get_by_role("textbox", name="API URL").count():
            raise RuntimeError("Business workspace exposed an editable API setting")
        if page.get_by_role("button", name="Về demo", exact=True).count():
            raise RuntimeError("Business workspace exposed the demo switch")
        with page.expect_response(
            lambda r: r.url.endswith("/api/v1/auth/verify")
            and r.request.method == "POST"
            and r.status == 200,
            timeout=45000,
        ) as verify_response:
            click(page, "Kết nối ví / Đăng nhập")
        tokens[key] = verify_response.value.json()["access_token"]
        button(page, "Tài khoản ví").wait_for(state="visible")
        return context, page

    with sync_playwright() as playwright:
        try:
            if api("/ready").get("status") != "ready":
                raise RuntimeError("API is not ready")
            config = api("/api/v1/config")
            if config["chain_id"] != 31337:
                raise RuntimeError("API does not use local chain31337")
            browser = playwright.chromium.launch(executable_path=args.browser, headless=True,
                args=["--disable-gpu", "--no-first-run"])
            merchant_context, merchant = open_session(browser, accounts[1], "merchant")
            record("merchant SIWE browser login")
            click(merchant, "Cơ sở")
            if merchant.get_by_role("button", name="Tạo hồ sơ cơ sở", exact=True).count():
                click(merchant, "Tạo hồ sơ cơ sở")
                form(merchant, {"Tên cơ sở": "Browser acceptance gym"})
            else:
                profile = api("/api/v1/me", tokens["merchant"])
                if not profile["is_merchant"]:
                    click(merchant, "Tạo hồ sơ cơ sở")
                    form(merchant, {"Tên cơ sở": "Browser acceptance gym"})
            click(merchant, "Tạo gói dịch vụ")
            form(merchant, {"Tên gói": plan_title, "Mô tả": "Local acceptance",
                "PG Credit mỗi kỳ": "50", "Số kỳ": "2", "Thời lượng mỗi kỳ": "6 giây", "Thời gian ân hạn": "1 phút"})
            plan = until(lambda: next((item for item in api("/api/v1/plans?limit=100")["items"]
                if item["title"] == plan_title), None))
            record("browser publish confirmed", plan_id=plan["plan_id"])
            with browser.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True) as guest_context:
                guest = guest_context.new_page()
                guest.goto(args.app_url, wait_until="networkidle")
                guest.locator("flt-semantics-placeholder").dispatch_event("click")
                button(guest, "Xem gói").wait_for(state="visible")
                guest.screenshot(path=str(args.output_dir / "guest-mobile.png"), full_page=True)
                click(guest, "Xem gói")
                guest.get_by_text(re.compile("Tổng trả trước: 100 PG Credit")).first.wait_for(state="visible")
                button(guest, "Kết nối ví để đăng ký").wait_for(state="visible")
                click(guest, "Hủy")
                click(guest, "Cơ sở")
                button(guest, "Kết nối ví").wait_for(state="visible")
                catalog_url = args.api_url.rstrip("/") + "/api/v1/plans?limit=20"
                guest.route(catalog_url, lambda route: route.fulfill(
                    status=503, content_type="application/json", body=json.dumps({
                        "error": {"code": "RPC_UNAVAILABLE", "message": "Catalog unavailable",
                                  "details": {}, "request_id": "catalog-fault-test"}}),
                    headers={"access-control-allow-origin": args.app_url.rstrip("/")},
                ))
                root_url = args.app_url.rstrip("/") + "/"
                guest.goto(root_url + f"?plan_id={plan['plan_id']}&chain_id={config['chain_id']}"
                           f"&vault={config['vault_address']}", wait_until="networkidle")
                guest.locator("flt-semantics-placeholder").dispatch_event("click")
                button(guest, "Tải lại danh mục").wait_for(state="visible")
                click(guest, "Xem gói")
                guest.get_by_text(re.compile("Tổng trả trước: 100 PG Credit")).first.wait_for(state="visible")
                click(guest, "Hủy")
                record("registration QR can open a plan when the catalog request fails")
                guest.unroute(catalog_url)
                guest.go_back(wait_until="domcontentloaded")
                guest.wait_for_url(root_url)
                record("one browser Back returns from registration QR to the previous document")
            record("guest can review published terms on mobile before signing in")
            customer_context, customer = open_session(browser, accounts[2], "customer")
            record("subscriber SIWE independent browser login")
            _, parallel_tab = open_session(
                browser, accounts[2], "parallel", customer_context,
                query="?demo=1&invite=gym-khoi-dong",
            )
            record("business root and legacy demo invite both use real API workspace")
            blocked_tracking_calls = []
            def tracking_outage(route):
                body = route.request.post_data_json
                if route.request.method == "POST" and body.get("action") == "SUBSCRIBE":
                    blocked_tracking_calls.append(True)
                    route.fulfill(status=503, content_type="application/json", body=json.dumps({
                        "error": {"code": "RPC_UNAVAILABLE", "message": "Injected test outage",
                                  "details": {}, "request_id": "cache-fault-test"}}))
                else:
                    route.continue_()
            if args.inject_cache_failure:
                customer_context.route("**/api/v1/transactions", tracking_outage)
            customer.evaluate("window.__testHoldNextVaultSend = true")
            click(customer, "Đăng ký")
            click(customer, "Tiếp tục ký ví")
            customer.wait_for_function("typeof window.__testReleaseVaultPrompt === 'function'")
            try:
                click(parallel_tab, "Đăng ký")
                click(parallel_tab, "Tiếp tục ký ví")
                parallel_tab.get_by_text(
                    "Ví đang xử lý một giao dịch trong tab khác.", exact=True,
                ).filter(visible=True).last.wait_for(state="visible")
                if parallel_tab.evaluate("window.__testTransactions.length") != 0:
                    raise RuntimeError("Second tab unexpectedly broadcast a transaction")
                record("same-origin second tab blocked while wallet prompt is open")
            finally:
                customer.evaluate("window.__testReleaseVaultPrompt()")
                parallel_tab.close()
            def membership():
                rows = api("/api/v1/me/subscriptions?limit=100", tokens["customer"])["items"]
                return next((item for item in rows if item["plan_id"] == plan["plan_id"]), None)
            sub = until(membership)
            sub_id = sub["subscription_id"]
            if args.inject_cache_failure:
                before_retry = len(customer.evaluate("window.__testTransactions"))
                until(lambda: blocked_tracking_calls)
                if customer.evaluate("window.__testPendingWriteFailures") < 1:
                    raise RuntimeError("Pending-cache fault was not actually exercised")
                # Repeating the financial intent during storage/API failure must emit no new wallet transaction.
                click(customer, "Đăng ký")
                click(customer, "Tiếp tục ký ví")
                customer.get_by_text(re.compile("Đã có giao dịch cùng thao tác đang chờ")).filter(visible=True).first.wait_for(state="visible")
                if len(customer.evaluate("window.__testTransactions")) != before_retry:
                    raise RuntimeError("Cache failure retry broadcast an additional transaction")
                if sum(item["plan_id"] == plan["plan_id"] for item in
                       api("/api/v1/me/subscriptions?limit=100", tokens["customer"])["items"]) != 1:
                    raise RuntimeError("Cache failure retry created duplicate subscriptions")
                customer.evaluate("window.__testFailPendingCache = false")
                customer_context.unroute("**/api/v1/transactions", tracking_outage)
                click(customer, "Làm mới trạng thái")
                # Observe actual tracking completion; a chain event alone is insufficient.
                until(lambda: any(tx["action"] == "SUBSCRIBE" and tx["status"] == "CONFIRMED"
                    for tx in customer.evaluate("""Object.keys(localStorage)
                      .filter(k => k.startsWith('prepaidguard.pending.'))
                      .flatMap(k => JSON.parse(localStorage.getItem(k)))""")))
                record("cache failure retains hash; retry emits no duplicate transaction; recovery confirms",
                    wallet_transaction_count=before_retry,
                    injected_write_failures=customer.evaluate("window.__testPendingWriteFailures"))
            record("browser approve and subscribe confirmed", subscription_id=sub_id)
            rpc(args.rpc_url, "evm_increaseTime", [7])
            rpc(args.rpc_url, "evm_mine", [])
            click(customer, "Làm mới trạng thái")
            click(customer, "Gói của tôi")
            click(customer, "Tạo QR check-in")
            qr = customer.get_by_text(re.compile(r'^\{"version":1,')).first
            qr.wait_for(state="visible")
            payload = qr.inner_text()
            message = json.loads(payload)
            if message["kind"] != "PREPAIDGUARD_CHECK_IN":
                raise RuntimeError("Unexpected QR payload")
            click(customer, "Đóng")
            record("browser signs and renders CheckIn QR",
                merchant_clock_skew_seconds=args.merchant_clock_skew,
                subscriber_clock_skew_seconds=args.subscriber_clock_skew)
            click(merchant, "Nhập QR check-in")
            form(merchant, {"QR payload": payload})
            click(merchant, "Tiếp tục ký ví")
            def detail():
                return api("/api/v1/subscriptions/" + sub_id, tokens["customer"])
            until(lambda: detail()["completed_periods"] == 1)
            record("merchant imports signed QR and release confirms")
            # The same QR is rejected before a second payment; RPC time is local-only.
            rpc(args.rpc_url, "evm_increaseTime", [7])
            rpc(args.rpc_url, "evm_mine", [])
            previous_count = len(merchant.evaluate("window.__testTransactions"))
            click(merchant, "Nhập QR check-in")
            form(merchant, {"QR payload": payload})
            click(merchant, "Tiếp tục ký ví")
            merchant.get_by_text(re.compile("QR đã dùng, sai kỳ hoặc chưa đủ điều kiện")).filter(visible=True).first.wait_for(state="visible", timeout=30000)
            if len(merchant.evaluate("window.__testTransactions")) != previous_count:
                raise RuntimeError("Replay unexpectedly broadcast another transaction")
            if detail()["completed_periods"] != 1:
                raise RuntimeError("Replay changed released periods")
            record("old QR replay rejected without extra payment")
            rpc(args.rpc_url, "evm_increaseTime", [70])
            rpc(args.rpc_url, "evm_mine", [])
            click(customer, "Làm mới trạng thái")
            click(customer, "Yêu cầu hoàn gốc")
            click(customer, "Tiếp tục ký ví")
            final = until(lambda: (value if (value := detail())["status"] == "REFUNDED" else None))
            expected = ("50000000", "50000000", "0")
            actual = tuple(final[name] for name in (
                "principal_released", "principal_refunded", "remaining_principal"))
            if actual != expected:
                raise RuntimeError("Final principal accounting mismatch")
            record("browser refund confirmed and principal conserved",
                principal_released=actual[0], principal_refunded=actual[1], remaining_principal=actual[2])
            click(customer, "Chi tiết / lịch sử")
            customer.get_by_text("Đã hoàn gốc: 50 PG Credit", exact=True).wait_for(state="visible")
            customer.get_by_text("Đã giải ngân: 50 PG Credit", exact=True).wait_for(state="visible")
            customer.get_by_text("Gốc còn lại: 0 PG Credit", exact=True).wait_for(state="visible")
            click(customer, "Đóng")
            record("real account detail displays on-chain principal and labelled yield")
            if args.test_replacement:
                customer.evaluate("window.__testFailPendingCache = false; window.__testPauseNextVaultSend = true")
                previous = len(customer.evaluate("window.__testTransactions"))
                click(customer, "Gói dịch vụ")
                try:
                    click(customer, "Đăng ký")
                    click(customer, "Tiếp tục ký ví")
                    until(lambda: len(customer.evaluate("window.__testTransactions")) > previous and
                        rpc(args.rpc_url, "eth_getTransactionByHash", [customer.evaluate("window.__testTransactions.at(-1)")])["to"].lower() == config["vault_address"].lower())
                    original_hash = customer.evaluate("window.__testTransactions.at(-1)")
                    def tracked_original():
                        try:
                            return api("/api/v1/transactions/" + original_hash, tokens["customer"])["sender_nonce"] is not None
                        except urllib.error.HTTPError:
                            return False
                    until(tracked_original)
                    original_tx = rpc(args.rpc_url, "eth_getTransactionByHash", [original_hash])
                    cancellation = rpc(args.rpc_url, "eth_sendTransaction", [{
                        "from": accounts[2], "to": accounts[2], "value": "0x0", "gas": "0x5208",
                        "nonce": original_tx["nonce"],
                        "gasPrice": hex(2 * int(original_tx.get("maxFeePerGas", original_tx["gasPrice"]), 16) + 10**9)}])
                    rpc(args.rpc_url, "evm_mine", [])
                finally:
                    rpc(args.rpc_url, "evm_setAutomine", [True])
                click(customer, "Giao dịch")
                click(customer, "Đối chiếu giao dịch tăng phí hoặc hủy trong ví")
                form(customer, {"Hash giao dịch mới": cancellation})
                until(lambda: api("/api/v1/transactions/" + original_hash, tokens["customer"])["status"] == "CANCELLED")
                record("browser reconciles confirmed cancellation without rebroadcasting")
                before_retry = len(api("/api/v1/me/subscriptions?limit=100", tokens["customer"])["items"])
                customer.evaluate("window.__testFailPendingCache = false")
                click(customer, "Gói dịch vụ")
                click(customer, "Đăng ký")
                click(customer, "Tiếp tục ký ví")
                until(lambda: len(api("/api/v1/me/subscriptions?limit=100", tokens["customer"])["items"]) == before_retry + 1)
                record("browser retries after cancellation and creates exactly one subscription")
            customer.screenshot(path=str(args.output_dir / "subscriber-final.png"), full_page=True)
            merchant.screenshot(path=str(args.output_dir / "merchant-final.png"), full_page=True)
            record("two independent browser contexts exercised",
                merchant_transactions=len(merchant.evaluate("window.__testTransactions")),
                subscriber_transactions=len(customer.evaluate("window.__testTransactions")))
            status = "pass"
            merchant_context.close()
            customer_context.close()
            browser.close()
        except Exception as error:
            results.append({"name": "browser acceptance", "status": "fail",
                "detail": type(error).__name__ + ": " + str(error)[:1200]})
            print(type(error).__name__ + ": acceptance failed; see report", flush=True)
            # Do not write authentication tokens, wallet signatures, traces or raw request bodies.
            if browser:
                try:
                    for index, context in enumerate(browser.contexts):
                        if context.pages:
                            context.pages[0].screenshot(
                                path=str(args.output_dir / ("failure-" + str(index) + ".png")),
                                full_page=True)
                    browser.close()
                except Exception:
                    pass
    report = {"timestamp_utc": started, "status": status, "steps": results,
        "scope": "Local EVM31337; test injected EIP1193 provider; no physical wallet/Fuji claims",
        "fault_injection": {"cache_failure": args.inject_cache_failure,
            "merchant_clock_skew_seconds": args.merchant_clock_skew,
            "subscriber_clock_skew_seconds": args.subscriber_clock_skew}}
    (args.output_dir / "browser-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if status == "pass" else 1)

if __name__ == "__main__":
    main()
