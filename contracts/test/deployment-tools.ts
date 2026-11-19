import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { artifacts, network } from "hardhat";
import { ZeroAddress, ZeroHash, MaxUint256, keccak256, toUtf8Bytes, type JsonRpcProvider, type TransactionResponse } from "ethers";
import { Attempt, positiveUint256, validateManifest, verifyDeployment, type Manifest } from "../scripts/lib/deployment.js";

const { ethers } = await network.create();
const provider = ethers.provider as unknown as JsonRpcProvider;

async function fixture(mode = "MOCK") {
  const [funder, treasury, outsider] = await ethers.getSigners();
  const token = await ethers.deployContract("MockUSDC", [funder.address]);
  const adapter = mode === "MOCK" ? await ethers.deployContract("MockYieldAdapter", [token.target, funder.address]) : null;
  const vault = await ethers.deployContract("PrepaidVault", [token.target, treasury.address, adapter?.target ?? ZeroAddress]);
  const steps: Record<string, any> = {};
  const step = async (name: string, tx: TransactionResponse) => {
    const receipt = await tx.wait();
    assert(receipt);
    steps[name] = { hash: receipt.hash, status: "confirmed", blockNumber: receipt.blockNumber,
      blockHash: receipt.blockHash, contractAddress: receipt.contractAddress };
  };
  await step("token", token.deploymentTransaction()!);
  if (adapter) await step("adapter", adapter.deploymentTransaction()!);
  await step("vault", vault.deploymentTransaction()!);
  if (adapter) await step("bind", await adapter.bindVault(vault.target));
  const checksums: Record<string, string> = {};
  const buildInfo: Record<string, { id: string; hash: string }> = {};
  for (const name of ["PrepaidVault", "MockUSDC", "MockYieldAdapter"]) {
    const artifact = await artifacts.readArtifact(name);
    assert(artifact.buildInfoId, "Compiled artifact must identify build info.");
    checksums[name] = keccak256(toUtf8Bytes(JSON.stringify(artifact.abi, null, 2) + "\n"));
    buildInfo[name] = { id: artifact.buildInfoId, hash: keccak256(await readFile(new URL(`../artifacts/build-info/${artifact.buildInfoId}.json`, import.meta.url))) };
  }
  const manifest = {
    chain_id: 31337, deployment_id: `31337-${String(vault.target).toLowerCase()}`, vault_address: String(vault.target),
    token: { address: String(token.target), decimals: 6 }, adapter_address: String(adapter?.target ?? ZeroAddress),
    treasury_address: treasury.address, deployer_address: funder.address, yield_mode: mode, confirmations: 1,
    deployment_block: steps.vault.blockNumber, deployment_tx_hash: steps.vault.hash,
    vault_code_hash: keccak256(await ethers.provider.getCode(vault.target)),
    evidence: { steps, constructor_args: { token: [funder.address], adapter: adapter ? [String(token.target), funder.address] : null,
      vault: [String(token.target), treasury.address, String(adapter?.target ?? ZeroAddress)] }, abi_keccak256: checksums, build_info: buildInfo },
  } as unknown as Manifest;
  return { funder, outsider, token, adapter, vault, manifest };
}

function overrideProvider(method: string, replacement: (...args: any[]) => any): JsonRpcProvider {
  return new Proxy(provider, { get(target, property) {
    if (property === method) return replacement;
    const value = Reflect.get(target, property, target);
    return typeof value === "function" ? value.bind(target) : value;
  } });
}

describe("Deployment tools", function () {
  this.timeout(60_000);
  let directory: string;
  beforeEach(async () => { directory = await mkdtemp(join(tmpdir(), "prepaidguard-tools-")); });
  afterEach(async () => {
    assert(directory.startsWith(join(tmpdir(), "prepaidguard-tools-")), "Cleanup target must be the test-owned temp directory.");
    await rm(directory, { recursive: true, force: true });
  });

  it("accepts uint256 edges and rejects noncanonical/overflow input before any transaction", async () => {
    const [funder] = await ethers.getSigners();
    const nonce = await funder.getNonce();
    assert.equal(positiveUint256("1"), 1n);
    assert.equal(positiveUint256(String(MaxUint256)), MaxUint256);
    for (const value of ["", "0", "-1", "+1", "01", "1.0", "1e3", " 1", "1\n", String(MaxUint256 + 1n)]) {
      assert.throws(() => positiveUint256(value), `Must reject ${JSON.stringify(value)}`);
    }
    assert.equal(await funder.getNonce(), nonce);
  });

  for (const mode of ["MOCK", "DISABLED"]) {
    it(`verifies real ${mode} deployment receipts and contract linkage`, async () => {
      const { manifest } = await fixture(mode);
      await verifyDeployment(provider, manifest);
    });
  }

  it("rejects chain, zero address, mode, precision, identity and confirmation mismatches", async () => {
    const { manifest } = await fixture();
    for (const patch of [
      { chain_id: 43113 }, { vault_address: ZeroAddress }, { treasury_address: ZeroAddress },
      { yield_mode: "BENQI" }, { adapter_address: ZeroAddress }, { token: { ...manifest.token, decimals: 18 } },
      { deployment_id: "31337-other" }, { confirmations: 0 }, { confirmations: 1.5 },
    ]) assert.throws(() => validateManifest({ ...manifest, ...patch }, 31337));
  });

  it("rejects changed financial target and missing code instead of accepting the fingerprint alone", async () => {
    const { manifest, outsider } = await fixture();
    await assert.rejects(verifyDeployment(provider, { ...manifest, treasury_address: outsider.address }));
    await assert.rejects(verifyDeployment(provider, { ...manifest, token: { address: outsider.address, decimals: 6 } }));
    await assert.rejects(verifyDeployment(provider, { ...manifest, vault_code_hash: ZeroHash }));
  });

  it("rejects missing, reverted, noncanonical and insufficiently confirmed receipts", async () => {
    const { manifest } = await fixture();
    const original = await provider.getTransactionReceipt(manifest.deployment_tx_hash);
    assert(original);
    for (const receipt of [null, { ...original, status: 0 }, { ...original, blockHash: ZeroHash }]) {
      const altered = overrideProvider("getTransactionReceipt", async (hash) => hash === manifest.deployment_tx_hash ? receipt : provider.getTransactionReceipt(hash));
      await assert.rejects(verifyDeployment(altered, manifest));
    }
    await assert.rejects(verifyDeployment(provider, { ...manifest, confirmations: 1_000_000 }));
    await assert.rejects(verifyDeployment(provider, { ...manifest, deployment_block: manifest.deployment_block + 1 }));
  });

  it("rejects deployment evidence with a wrong transaction or canonical block", async () => {
    const { manifest } = await fixture();
    const changed = structuredClone(manifest);
    assert(changed.evidence);
    changed.evidence.steps.token.hash = manifest.deployment_tx_hash;
    await assert.rejects(verifyDeployment(provider, changed));
    const stale = structuredClone(manifest);
    assert(stale.evidence);
    stale.evidence.steps.bind.blockHash = ZeroHash;
    await assert.rejects(verifyDeployment(provider, stale));
  });

  it("rejects constructor, ABI and build provenance mismatches against local artifacts", async () => {
    const { manifest, outsider } = await fixture();
    const constructor = structuredClone(manifest);
    constructor.evidence!.constructor_args!.vault![1] = outsider.address;
    await assert.rejects(verifyDeployment(provider, constructor));
    const abi = structuredClone(manifest);
    abi.evidence!.abi_keccak256!.PrepaidVault = ZeroHash;
    await assert.rejects(verifyDeployment(provider, abi));
    const build = structuredClone(manifest);
    build.evidence!.build_info!.PrepaidVault.hash = ZeroHash;
    await assert.rejects(verifyDeployment(provider, build));
  });

  it("rejects changed creation data even when the receipt and runtime fingerprint match", async () => {
    const { manifest } = await fixture();
    const altered = overrideProvider("getTransaction", async (hash) => {
      const tx = await provider.getTransaction(hash);
      return hash === manifest.deployment_tx_hash && tx ? { ...tx, data: tx.data + "00" } : tx;
    });
    await assert.rejects(verifyDeployment(altered, manifest));
  });

  it("rejects runtime source mismatch even after the manifest fingerprint is updated", async () => {
    const { manifest } = await fixture();
    const original = await provider.getCode(manifest.vault_address);
    // Change unreachable Solidity metadata, preserving operational getter behavior.
    const mutated = original.slice(0, -2) + (original.endsWith("00") ? "01" : "00");
    await ethers.provider.send("hardhat_setCode", [manifest.vault_address, mutated]);
    try {
      await assert.rejects(verifyDeployment(provider, { ...manifest, vault_code_hash: keccak256(mutated) }));
    } finally {
      await ethers.provider.send("hardhat_setCode", [manifest.vault_address, original]);
    }
  });

  it("bounds a genuinely pending transaction wait and leaves evidence for manual reconciliation", async () => {
    const [funder, recipient] = await ethers.getSigners();
    const attemptPath = join(directory, "pending-timeout");
    const attempt = await Attempt.create(attemptPath, {});
    const oldTimeout = process.env.TX_TIMEOUT_MS;
    process.env.TX_TIMEOUT_MS = "1000";
    await ethers.provider.send("evm_setAutomine", [false]);
    let hash = "";
    try {
      await assert.rejects(attempt.run("pending", async () => {
        const tx = await funder.sendTransaction({ to: recipient.address, value: 1n });
        hash = tx.hash;
        return tx;
      }, 1));
      const journal = JSON.parse(await readFile(join(attemptPath, "journal.json"), "utf8"));
      assert.equal(journal.steps.pending.hash, hash);
      assert.equal(journal.steps.pending.status, "unknown");
      assert.equal(await provider.getTransactionReceipt(hash), null);
      await assert.rejects(Attempt.create(attemptPath, {}));
    } finally {
      if (oldTimeout === undefined) delete process.env.TX_TIMEOUT_MS;
      else process.env.TX_TIMEOUT_MS = oldTimeout;
      await ethers.provider.send("evm_setAutomine", [true]);
      await ethers.provider.send("evm_mine", []);
    }
    assert.equal((await provider.getTransactionReceipt(hash))!.status, 1);
  });
  it("keeps the broadcast hash after receipt transport failure and refuses the same attempt", async () => {
    const [funder, recipient] = await ethers.getSigners();
    const attemptPath = join(directory, "receipt-lost");
    const attempt = await Attempt.create(attemptPath, { scope: "LOCAL_TEST" });
    const before = await funder.getNonce();
    let hash = "";
    await assert.rejects(attempt.run("fund", async () => {
      const tx = await funder.sendTransaction({ to: recipient.address, value: 1n });
      hash = tx.hash;
      return { hash, wait: async () => { throw new Error("Injected receipt transport failure"); } } as unknown as TransactionResponse;
    }, 1));
    const journal = JSON.parse(await readFile(join(attemptPath, "journal.json"), "utf8"));
    assert.equal(journal.steps.fund.hash, hash);
    assert.equal(journal.steps.fund.status, "unknown");
    assert.notEqual(journal.status, "complete");
    assert.equal(await funder.getNonce(), before + 1);
    await assert.rejects(Attempt.create(attemptPath, {}));
    let sentAgain = false;
    await assert.rejects(attempt.run("fund", async () => { sentAgain = true; throw new Error("Should not send"); }, 1));
    assert.equal(sentAgain, false);
    assert.equal(await funder.getNonce(), before + 1);
  });

  it("persists an unknown send intent even if acceptance happened before the caller received a hash", async () => {
    const [funder, recipient] = await ethers.getSigners();
    const attemptPath = join(directory, "send-lost");
    const attempt = await Attempt.create(attemptPath, {});
    const before = await funder.getNonce();
    await assert.rejects(attempt.run("send", async () => {
      await funder.sendTransaction({ to: recipient.address, value: 1n });
      throw new Error("Injected response loss after acceptance");
    }, 1));
    const journal = JSON.parse(await readFile(join(attemptPath, "journal.json"), "utf8"));
    assert.equal(journal.steps.send.status, "unknown");
    assert.equal(journal.steps.send.hash, undefined);
    assert.equal(await funder.getNonce(), before + 1);
    await assert.rejects(Attempt.create(attemptPath, {}));
  });

  it("keeps earlier confirmed work when a later step fails; a separate deliberate attempt is additive", async () => {
    const [funder, recipient] = await ethers.getSigners();
    const token = await ethers.deployContract("MockUSDC", [funder.address]);
    const attemptPath = join(directory, "mint-then-fail");
    const attempt = await Attempt.create(attemptPath, {});
    await attempt.run("mint", () => token.mint(recipient.address, 7n), 1);
    await assert.rejects(attempt.run("approve", async () => { throw new Error("Injected failure before approval"); }, 1));
    const journal = JSON.parse(await readFile(join(attemptPath, "journal.json"), "utf8"));
    assert.equal(journal.steps.mint.status, "confirmed");
    assert.equal(journal.steps.approve.status, "unknown");
    assert.equal(await token.balanceOf(recipient.address), 7n);
    await assert.rejects(Attempt.create(attemptPath, {}));
    const next = await Attempt.create(join(directory, "explicit-next"), {});
    await next.run("mint", () => token.mint(recipient.address, 3n), 1);
    await next.complete();
    assert.equal(await token.balanceOf(recipient.address), 10n);
    assert.equal(JSON.parse(await readFile(join(directory, "explicit-next", "journal.json"), "utf8")).status, "complete");
  });
});