import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { createServer as createHttpServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { Contract, JsonRpcProvider, MaxUint256, ZeroAddress, id } from "ethers";
import { checkInTypes } from "./signing.js";

// Always owns its node. This runner cannot target Fuji or an existing demo node.
const root = fileURLToPath(new URL("../", import.meta.url));
const cli = join(root, "node_modules", "hardhat", "dist", "src", "cli.js");
const output = await mkdtemp(join(tmpdir(), "prepaidguard-rehearsal-"));
const report: { scope: string; modes: unknown[]; faults: unknown[]; status: string; error?: string; owned_node?: { pid: number | undefined; rpc: string; closed: boolean } } = {
  scope: "LOCAL_ONLY_CHAIN_31337", modes: [], faults: [], status: "RUNNING",
};
const safeError = (error: unknown) => String(error).replace(/https?:\/\/[^\s"']+/g, "[URL omitted]");
const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const port = await new Promise<number>((resolve, reject) => {
  const server = createServer();
  server.once("error", reject);
  server.listen(0, "127.0.0.1", () => {
    const address = server.address();
    if (!address || typeof address === "string") return reject(new Error("No loopback port."));
    server.close((error) => error ? reject(error) : resolve(address.port));
  });
});
const rpc = `http://127.0.0.1:${port}`;
const node = spawn(process.execPath, [cli, "node", "--hostname", "127.0.0.1", "--port", String(port)], {
  cwd: root, stdio: "ignore", windowsHide: true,
});
report.owned_node = { pid: node.pid, rpc, closed: false };
const provider = new JsonRpcProvider(rpc, 31337, { staticNetwork: true, cacheTimeout: -1 });

async function command(script: string, env: NodeJS.ProcessEnv, expectFailure = false) {
  return await new Promise<void>((resolve, reject) => {
    const child = spawn(process.execPath, [cli, "run", `scripts/${script}.ts`, "--network", "localhost"], {
      cwd: root, env: { ...process.env, RPC_URL: rpc, EXPECTED_CHAIN_ID: "31337", ...env },
      stdio: ["ignore", "pipe", "pipe"], windowsHide: true,
    });
    let diagnostics = "";
    child.stdout.on("data", (chunk) => { diagnostics = (diagnostics + chunk).slice(-6000); });
    child.stderr.on("data", (chunk) => { diagnostics = (diagnostics + chunk).slice(-6000); });
    const timeout = setTimeout(() => { child.kill(); reject(new Error(`${script} timed out.`)); }, 90_000);
    child.once("error", (error) => { clearTimeout(timeout); reject(error); });
    child.once("exit", (code) => {
      clearTimeout(timeout);
      if (expectFailure ? code !== 0 : code === 0) resolve();
      else reject(new Error(`${script} unexpected exit ${code}: ${safeError(diagnostics)}`));
    });
  });
}

// Fail at the HTTP boundary only after the real local node accepted a send.
// Production deployment code has no fault switches or special paths.
async function faultProxy(interruptAt: number) {
  const stats = { accepted_sends: 0, blocked_retries: 0, withheld_hash: "" };
  const server = createHttpServer(async (request, response) => {
    try {
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      const input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      const forward = async (message: { id?: number | string; method?: string }) => {
        const send = message.method === "eth_sendTransaction" || message.method === "eth_sendRawTransaction";
        const failure = () => ({ jsonrpc: "2.0", id: message.id, error: {
          code: -32000, message: "Injected local response loss after transaction acceptance.",
        } });
        if (send && stats.withheld_hash) {
          stats.blocked_retries++;
          return failure();
        }
        const upstream = await fetch(rpc, { method: "POST", headers: { "content-type": "application/json" },
          body: JSON.stringify(message), signal: AbortSignal.timeout(10_000) });
        assert(upstream.ok, "Owned RPC proxy upstream HTTP request failed.");
        const result = await upstream.json() as { result?: string };
        if (send && typeof result.result === "string") {
          stats.accepted_sends++;
          if (stats.accepted_sends === interruptAt) {
            stats.withheld_hash = result.result;
            return failure();
          }
        }
        return result;
      };
      const replies = [];
      for (const message of Array.isArray(input) ? input : [input]) replies.push(await forward(message));
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify(Array.isArray(input) ? replies : replies[0]));
    } catch {
      response.writeHead(502, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "Local fault proxy failed." }));
    }
  });
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  assert(address && typeof address !== "string");
  return { url: `http://127.0.0.1:${address.port}`, stats, close: async () => {
    const closed = new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
    server.closeAllConnections();
    await closed;
  } };
}
try {
  let ready = false;
  for (let attempt = 0; attempt < 120; attempt++) {
    if (node.exitCode !== null) throw new Error("Owned Hardhat node exited before readiness.");
    try { ready = await provider.send("eth_chainId", []) === "0x7a69"; } catch { /* startup */ }
    if (ready) break;
    await pause(250);
  }
  assert(ready, "Owned loopback node must report chain 31337.");
  const [funder, merchant, subscriber, treasury] = await Promise.all([0, 1, 2, 3].map((i) => provider.getSigner(i)));
  const [funderAddress, merchantAddress, subscriberAddress, treasuryAddress] = await Promise.all(
    [funder, merchant, subscriber, treasury].map((signer) => signer.getAddress()),
  );
  const deploymentSteps = ["token", "adapter", "vault", "bind"];
  for (let nth = 1; nth <= deploymentSteps.length; nth++) {
    const caseDir = join(output, `fault-after-${deploymentSteps[nth - 1]}`);
    await mkdir(caseDir, { recursive: true });
    const manifestPath = join(caseDir, "manifest.json");
    const attemptDir = join(caseDir, "attempt");
    const proxy = await faultProxy(nth);
    const row: Record<string, unknown> = { interrupted_step: deploymentSteps[nth - 1], status: "RUNNING",
      manifest: manifestPath, journal: join(attemptDir, "journal.json"), ...proxy.stats };
    report.faults.push(row);
    const env: NodeJS.ProcessEnv = { RPC_URL: proxy.url, EXPECTED_CHAIN_ID: "31337", YIELD_MODE: "MOCK",
      TREASURY_ADDRESS: treasuryAddress, MANIFEST_PATH: manifestPath, ATTEMPT_DIR: attemptDir };
    const before = await provider.getTransactionCount(funderAddress);
    try {
      await command("deploy", env, true);
      assert.equal(proxy.stats.accepted_sends, nth, "Each earlier step and the interrupted send must be accepted exactly once.");
      assert.equal(proxy.stats.blocked_retries, 0, "Deploy must not auto-retry a send after response loss.");
      assert.match(proxy.stats.withheld_hash, /^0x[0-9a-fA-F]{64}$/);
      assert.equal(await provider.getTransactionCount(funderAddress), before + nth, "No extra deployment transaction may be sent.");
      await assert.rejects(readFile(manifestPath), { code: "ENOENT" });
      const journal = JSON.parse(await readFile(join(attemptDir, "journal.json"), "utf8"));
      assert.notEqual(journal.status, "complete");
      assert.deepEqual(Object.keys(journal.steps), deploymentSteps.slice(0, nth));
      for (const label of deploymentSteps.slice(0, nth - 1)) {
        assert.equal(journal.steps[label].status, "confirmed");
        assert.equal((await provider.getTransactionReceipt(journal.steps[label].hash))!.status, 1);
      }
      const interrupted = journal.steps[deploymentSteps[nth - 1]];
      assert.equal(interrupted.status, "unknown");
      assert.equal(interrupted.hash, undefined, "Caller did not receive the accepted transaction hash.");
      const withheldReceipt = await provider.getTransactionReceipt(proxy.stats.withheld_hash);
      assert(withheldReceipt && withheldReceipt.status === 1, "Interruption must happen after actual chain acceptance.");
      // A second invocation with the same attempt must stop before any new send.
      await command("deploy", env, true);
      assert.equal(proxy.stats.blocked_retries, 0);
      assert.equal(await provider.getTransactionCount(funderAddress), before + nth);
      row.status = "PASS";
      row.nonce_before = before;
      row.nonce_after = before + nth;
      row.accepted_receipt_block = withheldReceipt.blockNumber;
    } catch (error) {
      row.status = "FAIL";
      row.error = safeError(error);
      throw error;
    } finally {
      Object.assign(row, proxy.stats);
      await proxy.close();
      await writeFile(join(caseDir, "fault.json"), JSON.stringify(row, null, 2) + "\n");
    }
  }
  const abi = async (name: string) => JSON.parse(await readFile(join(root, "..", "shared", "abi", `${name}.json`), "utf8"));
  for (const mode of ["MOCK", "DISABLED"]) {
    const modeDir = join(output, mode.toLowerCase());
    const manifestPath = join(modeDir, "manifest.json");
    const common: NodeJS.ProcessEnv = {
      MANIFEST_PATH: manifestPath, TREASURY_ADDRESS: treasuryAddress, YIELD_MODE: mode,
      MERCHANT_ADDRESS: merchantAddress, SUBSCRIBER_ADDRESS: subscriberAddress,
      DEPLOYER_ADDRESS: funderAddress,
    };
    const operation = (name: string) => ({ ...common, ATTEMPT_DIR: join(modeDir, name), SEED_EVIDENCE_PATH: join(modeDir, `${name}.seed.json`) });
    await command("preflight", { ...common, DEPLOYER_PRIVATE_KEY: undefined, GAS_BUDGET_WEI: "1000000000000000000" });
    await command("deploy", operation("deploy"));
    // The read-only path must work without any signer secret.
    await command("verify-deployment", { ...common, DEPLOYER_PRIVATE_KEY: undefined });
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    const protectedNonce = await provider.getTransactionCount(funderAddress);
    await command("deploy", operation("deploy-repeat"), true);
    await command("preflight", { ...common, EXPECTED_CHAIN_ID: "43113", DEPLOYER_PRIVATE_KEY: undefined, GAS_BUDGET_WEI: "1" }, true);
    assert.equal(await provider.getTransactionCount(funderAddress), protectedNonce);
    assert.equal(manifest.chain_id, 31337);
    assert.equal(manifest.yield_mode, mode);
    const token = new Contract(manifest.token.address, await abi("MockUSDC"), funder);
    const vault = new Contract(manifest.vault_address, await abi("PrepaidVault"), merchant);
    const customerVault = vault.connect(subscriber) as Contract;
    const customerToken = token.connect(subscriber) as Contract;
    const adapter = mode === "MOCK" ? new Contract(manifest.adapter_address, await abi("MockYieldAdapter"), funder) : null;
    if (!adapter) assert.equal(manifest.adapter_address, ZeroAddress);

    await command("seed-demo", operation("seed-first"));
    const seeded = await token.balanceOf(subscriberAddress) as bigint;
    assert(seeded >= 500_000_000n);
    const seedNonce = await provider.getTransactionCount(funderAddress);
    await command("seed-demo", operation("seed-repeat"));
    assert.equal(await token.balanceOf(subscriberAddress), seeded);
    assert.equal(await provider.getTransactionCount(funderAddress), seedNonce, "Seed repeat must not broadcast.");

    // Inputs fail before mint/approve, including nonexistent positions and DISABLED mode.
    for (const [name, subscriptionId, amount] of [["invalid-id", "999999", "1"], ["overflow", "1", String(2n ** 256n)]]) {
      const before = await provider.getTransactionCount(funderAddress);
      await command("fund-yield", { ...operation(name), SUBSCRIPTION_ID: subscriptionId, YIELD_AMOUNT: amount }, true);
      assert.equal(await provider.getTransactionCount(funderAddress), before, "Invalid funding must not broadcast.");
    }
    const tamperedPath = join(modeDir, "tampered.json");
    await writeFile(tamperedPath, JSON.stringify({ ...manifest, treasury_address: merchantAddress }));
    const readOnlyNonce = await provider.getTransactionCount(funderAddress);
    await command("verify-deployment", { ...common, MANIFEST_PATH: tamperedPath, DEPLOYER_PRIVATE_KEY: undefined }, true);
    assert.equal(await provider.getTransactionCount(funderAddress), readOnlyNonce);

    const participants = [funderAddress, merchantAddress, subscriberAddress, treasuryAddress, manifest.vault_address,
      ...(adapter ? [manifest.adapter_address] : [])];
    const total = async () => (await Promise.all(participants.map((address) => token.balanceOf(address) as Promise<bigint>)))
      .reduce((sum, balance) => sum + balance, 0n);
    const initial = await total();
    const merchantBefore = await token.balanceOf(merchantAddress) as bigint;
    const customerBefore = await token.balanceOf(subscriberAddress) as bigint;
    const treasuryBefore = await token.balanceOf(treasuryAddress) as bigint;
    const hashes: Record<string, string> = {};
    const mine = async (name: string, tx: Promise<any>) => {
      const response = await tx;
      const receipt = await response.wait();
      assert.equal(receipt.status, 1);
      hashes[name] = receipt.hash;
      return receipt;
    };
    const at = async (timestamp: bigint) => {
      const block = await provider.send("eth_getBlockByNumber", ["latest", false]);
      await provider.send("evm_setNextBlockTimestamp", [Number(timestamp > BigInt(block.timestamp) ? timestamp : BigInt(block.timestamp) + 1n)]);
    };
    await mine("publish", vault.createPlan(id(`rehearsal-${mode}`), manifest.token.address, 50_000_000n, 2, 1000, 2000));
    const planId = await vault.planCount();
    await mine("approve", customerToken.approve(vault.target, MaxUint256));
    await mine("subscribeA", customerVault.subscribe(planId));
    const a = await vault.subscriptionCount() as bigint;
    await mine("subscribeB", customerVault.subscribe(planId));
    const b = await vault.subscriptionCount() as bigint;
    const domain = { name: "PrepaidGuard", version: "1", chainId: 31337, verifyingContract: manifest.vault_address };
    const release = async (subscriptionId: bigint, name: string) => {
      const sub = await vault.getSubscription(subscriptionId);
      const message = { subscriptionId, merchant: merchantAddress, periodIndex: sub.completedPeriods + 1n,
        nonce: sub.nonce, deadline: sub.nextReleaseAt + 600n };
      const signature = await subscriber.signTypedData(domain, checkInTypes, message);
      await at(sub.nextReleaseAt);
      await mine(name, vault.checkInWithSignature(message, signature));
      const settled = await vault.getSubscription(subscriptionId);
      assert.equal(settled.nonce, sub.nonce + 1n);
      await assert.rejects(vault.checkInWithSignature.staticCall(message, signature));
      return settled;
    };
    if (adapter) await command("fund-yield", { ...operation("yield-a"), SUBSCRIPTION_ID: String(a), YIELD_AMOUNT: "101" });
    await release(a, "releaseA1");
    await release(b, "releaseB1");
    if (adapter) await command("fund-yield", { ...operation("yield-b"), SUBSCRIPTION_ID: String(b), YIELD_AMOUNT: "21" });
    const completed = await release(a, "releaseA2");
    assert.equal(completed.status, 2n);
    assert.equal(completed.remainingPrincipal, 0n);
    assert.equal(completed.nextReleaseAt, 0n);
    const partial = await vault.getSubscription(b);
    assert.equal(partial.remainingPrincipal, 50_000_000n);
    await at(partial.nextReleaseAt + 2000n);
    await mine("refundB", customerVault.refund(b));
    const refunded = await vault.getSubscription(b);
    assert.equal(refunded.status, 3n);
    assert.equal(refunded.nonce, 2n);
    await assert.rejects(customerVault.refund.staticCall(b));
    if (adapter) {
      assert.equal(await adapter.totalPrincipal(), 0n);
      assert.equal(await adapter.totalYield(), 0n);
    }
    assert.equal(await vault.totalPrincipal(), 0n);
    assert.equal(await token.balanceOf(merchantAddress) - merchantBefore, 150_000_000n + (adapter ? 84n : 0n));
    assert.equal(await token.balanceOf(subscriberAddress) - customerBefore, -150_000_000n + (adapter ? 24n : 0n));
    assert.equal(await token.balanceOf(treasuryAddress) - treasuryBefore, adapter ? 14n : 0n);
    assert.equal(await total(), initial + (adapter ? 122n : 0n), "Token conservation across all custodians and recipients.");
    const beforeTerminal = await provider.getTransactionCount(funderAddress);
    await command("fund-yield", { ...operation("terminal-yield"), SUBSCRIPTION_ID: String(b), YIELD_AMOUNT: "1" }, true);
    assert.equal(await provider.getTransactionCount(funderAddress), beforeTerminal);
    report.modes.push({ mode, status: "PASS", deployment_id: manifest.deployment_id, manifest: manifestPath,
      subscriptions: { completed: String(a), refunded: String(b) }, hashes, total_atomic: String(await total()),
      local_artifact_verification: manifest.evidence.local_artifact_verification, source_verification: manifest.evidence.source_verification });
  }
  report.status = "PASS";
} catch (error) {
  report.status = "FAIL";
  report.error = safeError(error);
  process.exitCode = 1;
} finally {
  provider.destroy();
  if (node.exitCode === null) {
    node.kill();
    await Promise.race([new Promise((resolve) => node.once("exit", resolve)), pause(5000)]);
  }
  report.owned_node.closed = node.exitCode !== null || node.signalCode !== null;
  if (!report.owned_node.closed) { report.status = "FAIL"; report.error = "Owned node did not close."; process.exitCode = 1; }
  const reportPath = join(output, "report.json");
  await writeFile(reportPath, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ status: report.status, scope: report.scope, report: reportPath }));
}