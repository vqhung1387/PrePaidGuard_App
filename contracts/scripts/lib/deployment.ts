import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Contract, ContractFactory, Interface, getAddress, JsonRpcProvider, keccak256, MaxUint256, toUtf8Bytes, ZeroAddress, type TransactionResponse } from "ethers";

export const vaultAbi = ["function paymentToken() view returns (address)", "function treasury() view returns (address)", "function adapter() view returns (address)", "function eip712Domain() view returns (bytes1 fields,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt,uint256[] extensions)", "function getSubscription(uint256) view returns ((uint256 planId,address subscriber,uint256 initialPrincipal,uint256 remainingPrincipal,uint32 completedPeriods,uint256 nonce,uint64 startedAt,uint64 nextReleaseAt,uint8 status))"];
export const tokenAbi = ["function owner() view returns (address)", "function decimals() view returns (uint8)"];
export const adapterAbi = ["function token() view returns (address)", "function funder() view returns (address)", "function vault() view returns (address)", "function principalOf(uint256) view returns (uint256)"];
export type Manifest = { chain_id: number; deployment_id: string; vault_address: string; token: { address: string; decimals: number }; adapter_address: string; treasury_address: string; deployer_address: string; yield_mode: string; confirmations: number; deployment_block: number; deployment_tx_hash: string; vault_code_hash: string; evidence?: { steps: Record<string, Step>; constructor_args?: Record<string, unknown[] | null>; abi_keccak256?: Record<string, string>; build_info?: Record<string, { id: string; hash: string }> } };
type Step = { hash?: string; status: string; blockNumber?: number; blockHash?: string; contractAddress?: string | null; gasUsed?: string; gasPrice?: string };
export function validateChain(chainId: number): void {
  if (![31337, 43113].includes(chainId) || (process.env.EXPECTED_CHAIN_ID !== undefined && Number(process.env.EXPECTED_CHAIN_ID) !== chainId)) throw new Error("EXPECTED_CHAIN_ID must match the connected chain (31337 or 43113).");
}
export async function requireGasBudget(provider: { getBalance(address: string): Promise<bigint> }, chainId: number, signer: string): Promise<void> {
  if (chainId !== 43113) return;
  const budget = positiveUint256(process.env.GAS_BUDGET_WEI ?? "");
  if (await provider.getBalance(signer) < budget) throw new Error("Balance below declared gas budget.");
}
export function positiveUint256(value: string): bigint {
  if (!/^[1-9][0-9]*$/.test(value)) throw new Error("Expected a positive uint256 decimal string.");
  const n = BigInt(value); if (n > MaxUint256) throw new Error("Value exceeds uint256."); return n;
}
export function address(value: unknown, label: string, allowZero = false): string {
  if (typeof value !== "string") throw new Error(`Invalid ${label}.`);
  let a: string; try { a = getAddress(value); } catch { throw new Error(`Invalid ${label}.`); }
  if (!allowZero && a === ZeroAddress) throw new Error(`Invalid ${label}.`); return a;
}
export function validateManifest(m: Manifest, chainId: number): void {
  if (![31337, 43113].includes(chainId) || m.chain_id !== chainId) throw new Error("Manifest chain mismatch.");
  const vault = address(m.vault_address, "vault"); address(m.token?.address, "token"); address(m.treasury_address, "treasury"); address(m.deployer_address, "deployer");
  const adapter = address(m.adapter_address, "adapter", true);
  if (!["MOCK", "DISABLED"].includes(m.yield_mode) || (m.yield_mode === "MOCK") !== (adapter !== ZeroAddress)) throw new Error("Invalid mode or adapter.");
  if (m.token.decimals !== 6 || !Number.isSafeInteger(m.confirmations) || m.confirmations < (chainId === 43113 ? 2 : 1)) throw new Error("Invalid decimals or confirmations.");
  if (m.deployment_id !== `${chainId}-${vault.toLowerCase()}` || !Number.isSafeInteger(m.deployment_block) || m.deployment_block < 0 || !/^0x[0-9a-fA-F]{64}$/.test(m.deployment_tx_hash) || !/^0x[0-9a-fA-F]{64}$/.test(m.vault_code_hash)) throw new Error("Invalid deployment identity or evidence.");
}
export function manifestPath(chainId: number): string {
  return resolve(process.env.MANIFEST_PATH ?? fileURLToPath(new URL(`../../../shared/deployments/${chainId === 43113 ? "fuji" : "local"}.json`, import.meta.url)));
}
export async function readManifest(chainId: number): Promise<Manifest> {
  const m = JSON.parse(await readFile(manifestPath(chainId), "utf8")) as Manifest; validateManifest(m, chainId); return m;
}
export function readProvider(): { provider: JsonRpcProvider; chainId: number } {
  const chainId = Number(process.env.EXPECTED_CHAIN_ID);
  if (![31337, 43113].includes(chainId)) throw new Error("Set EXPECTED_CHAIN_ID to 31337 or 43113.");
  const url = process.env.RPC_URL ?? (chainId === 43113 ? process.env.FUJI_RPC_URL ?? "https://api.avax-test.network/ext/bc/C/rpc" : "http://127.0.0.1:8545");
  return { provider: new JsonRpcProvider(url), chainId };
}
export async function verifyDeployment(provider: JsonRpcProvider, m: Manifest): Promise<void> {
  const chainId = Number((await provider.getNetwork()).chainId); validateManifest(m, chainId);
  const same = (actual: string, expected: string, label: string) => { if (getAddress(actual) !== getAddress(expected)) throw new Error(`${label} mismatch.`); };
  const code = await provider.getCode(m.vault_address); if (code === "0x" || keccak256(code) !== m.vault_code_hash) throw new Error("Vault code fingerprint mismatch.");
  if (await provider.getCode(m.token.address) === "0x") throw new Error("Token code missing.");
  const vault = new Contract(m.vault_address, vaultAbi, provider), token = new Contract(m.token.address, tokenAbi, provider);
  same(await vault.paymentToken(), m.token.address, "Vault token"); same(await vault.treasury(), m.treasury_address, "Treasury"); same(await vault.adapter(), m.adapter_address, "Vault adapter");
  const domain = await vault.eip712Domain(); if (domain.name !== "PrepaidGuard" || domain.version !== "1" || domain.chainId !== BigInt(chainId)) throw new Error("EIP-712 domain mismatch."); same(domain.verifyingContract, m.vault_address, "EIP-712 verifying contract");
  same(await token.owner(), m.deployer_address, "Token owner"); if (Number(await token.decimals()) !== 6) throw new Error("Token decimals mismatch.");
  if (m.yield_mode === "MOCK") {
    if (await provider.getCode(m.adapter_address) === "0x") throw new Error("Adapter code missing.");
    const adapter = new Contract(m.adapter_address, adapterAbi, provider);
    same(await adapter.token(), m.token.address, "Adapter token"); same(await adapter.vault(), m.vault_address, "Adapter vault"); same(await adapter.funder(), m.deployer_address, "Adapter funder");
  }
  const checkReceipt = async (hash: string, blockNumber?: number, blockHash?: string) => {
    const receipt = await provider.getTransactionReceipt(hash); if (!receipt || receipt.status !== 1) throw new Error("Receipt missing or failed.");
    const block = await provider.getBlock(receipt.blockNumber); if (!block || block.hash !== receipt.blockHash || (blockNumber !== undefined && receipt.blockNumber !== blockNumber) || (blockHash && receipt.blockHash !== blockHash)) throw new Error("Receipt is not canonical.");
    if ((await provider.getBlockNumber()) - receipt.blockNumber + 1 < m.confirmations) throw new Error("Insufficient confirmations."); return receipt;
  };
  const receipt = await checkReceipt(m.deployment_tx_hash, m.deployment_block); same(receipt.contractAddress ?? ZeroAddress, m.vault_address, "Deployed vault");
  if (m.evidence) {
    for (const key of ["token", ...(m.yield_mode === "MOCK" ? ["adapter"] : []), "vault", ...(m.yield_mode === "MOCK" ? ["bind"] : [])]) {
      const step = m.evidence.steps[key]; if (!step || step.status !== "confirmed") throw new Error("Deployment evidence incomplete.");
      if (!step.hash) throw new Error("Deployment transaction hash missing."); const r = await checkReceipt(step.hash, step.blockNumber, step.blockHash);
      if (key === "token") same(r.contractAddress ?? ZeroAddress, m.token.address, "Deployed token");
      if (key === "adapter") same(r.contractAddress ?? ZeroAddress, m.adapter_address, "Deployed adapter");
      if (key === "vault") same(r.contractAddress ?? ZeroAddress, m.vault_address, "Deployed vault");
      const tx = await provider.getTransaction(step.hash); if (!tx) throw new Error("Deployment transaction missing.");
      same(tx.from, m.deployer_address, "Transaction sender");
      if (key === "bind") {
        same(tx.to ?? ZeroAddress, m.adapter_address, "Bind target");
        const expected = new Interface(["function bindVault(address)"]).encodeFunctionData("bindVault", [m.vault_address]);
        if (tx.data.toLowerCase() !== expected.toLowerCase()) throw new Error("Bind calldata mismatch.");
      } else if (tx.to !== null) throw new Error("Expected contract creation.");
    }
    if (m.evidence.constructor_args && m.evidence.abi_keccak256 && m.evidence.build_info) await verifyArtifacts(provider, m);
  }
}
export async function verifyArtifacts(provider: JsonRpcProvider, m: Manifest): Promise<void> {
  const evidence = m.evidence;
  if (!evidence?.constructor_args || !evidence.abi_keccak256 || !evidence.build_info) throw new Error("Artifact evidence missing.");
  const entries = [
    { key: "token", name: "MockUSDC", path: "mocks/MockUSDC.sol", address: m.token.address },
    ...(m.yield_mode === "MOCK" ? [{ key: "adapter", name: "MockYieldAdapter", path: "mocks/MockYieldAdapter.sol", address: m.adapter_address }] : []),
    { key: "vault", name: "PrepaidVault", path: "PrepaidVault.sol", address: m.vault_address },
  ];
  for (const entry of entries) {
    const artifact = JSON.parse(await readFile(fileURLToPath(new URL(`../../artifacts/contracts/${entry.path}/${entry.name}.json`, import.meta.url)), "utf8"));
    if (Object.keys(artifact.linkReferences ?? {}).length || Object.keys(artifact.deployedLinkReferences ?? {}).length) throw new Error("Linked artifacts unsupported.");
    const info = evidence.build_info[entry.name];
    if (!info || info.id !== artifact.buildInfoId) throw new Error("Build info identity mismatch.");
    const build = await readFile(fileURLToPath(new URL(`../../artifacts/build-info/${info.id}.json`, import.meta.url)));
    if (keccak256(build) !== info.hash || keccak256(toUtf8Bytes(JSON.stringify(artifact.abi, null, 2) + "\n")) !== evidence.abi_keccak256[entry.name]) throw new Error("Artifact or build info mismatch.");
    const args = evidence.constructor_args[entry.key]; const step = evidence.steps[entry.key];
    if (!args || !step?.hash) throw new Error("Constructor evidence missing.");
    const tx = await provider.getTransaction(step.hash); const expected = await new ContractFactory(artifact.abi, artifact.bytecode).getDeployTransaction(...args);
    if (!tx || tx.to !== null || tx.data.toLowerCase() !== expected.data?.toLowerCase()) throw new Error("Creation bytecode or constructor mismatch.");
    const actual = Buffer.from((await provider.getCode(entry.address)).slice(2), "hex"); const reference = Buffer.from(artifact.deployedBytecode.slice(2), "hex");
    if (actual.length !== reference.length) throw new Error("Runtime bytecode length mismatch.");
    for (const spans of Object.values(artifact.immutableReferences ?? {}) as Array<Array<{ start: number; length: number }>>) for (const span of spans) {
      if (span.start < 0 || span.length <= 0 || span.start + span.length > reference.length) throw new Error("Invalid immutable span.");
      actual.fill(0, span.start, span.start + span.length); reference.fill(0, span.start, span.start + span.length);
    }
    if (!actual.equals(reference)) throw new Error("Runtime bytecode mismatch.");
  }
}
export async function writeJson(path: string, value: unknown): Promise<void> {
  await mkdir(dirname(path), { recursive: true }); const tmp = `${path}.tmp`; await writeFile(tmp, JSON.stringify(value, null, 2) + "\n", { flag: "wx" }); await rename(tmp, path);
}
export class Attempt {
  private constructor(public readonly dir: string, public readonly data: { status: string; metadata: unknown; steps: Record<string, Step> }) {}
  static async create(dir: string, metadata: unknown): Promise<Attempt> {
    await mkdir(dirname(dir), { recursive: true }); await mkdir(dir); const attempt = new Attempt(dir, { status: "in_progress", metadata, steps: {} }); await attempt.save(); return attempt;
  }
  async save(): Promise<void> { await writeJson(resolve(this.dir, "journal.json"), this.data); }
  async run(label: string, send: () => Promise<TransactionResponse>, confirmations: number) {
    const timeout = Number(process.env.TX_TIMEOUT_MS ?? "120000"); if (!Number.isSafeInteger(timeout) || timeout < 1000 || timeout > 600000) throw new Error("Invalid TX_TIMEOUT_MS (1000-600000).");
    if (this.data.steps[label]) throw new Error("Step already exists; reconcile manually.");
    this.data.steps[label] = { status: "intent" }; await this.save();
    let tx: TransactionResponse; try { tx = await send(); } catch { this.data.steps[label].status = "unknown"; await this.save(); throw new Error(`Transaction ${label} broadcast uncertain; reconcile manually.`); }
    this.data.steps[label] = { hash: tx.hash, status: "broadcast" }; await this.save();
    try {
      const receipt = await tx.wait(confirmations, timeout); if (!receipt) throw new Error("Receipt unavailable.");
      this.data.steps[label] = { hash: tx.hash, status: receipt.status === 1 ? "confirmed" : "reverted", blockNumber: receipt.blockNumber, blockHash: receipt.blockHash, contractAddress: receipt.contractAddress, gasUsed: receipt.gasUsed.toString(), gasPrice: receipt.gasPrice.toString() }; await this.save();
      if (receipt.status !== 1) throw new Error("Transaction reverted."); return receipt;
    } catch (error) { const receipt = (error as { receipt?: { status: number; blockNumber: number; blockHash: string; contractAddress: string | null; gasUsed: bigint; gasPrice: bigint } }).receipt;
      if (receipt?.status === 0) { this.data.steps[label] = { hash: tx.hash, status: "reverted", blockNumber: receipt.blockNumber, blockHash: receipt.blockHash, contractAddress: receipt.contractAddress, gasUsed: receipt.gasUsed.toString(), gasPrice: receipt.gasPrice.toString() }; await this.save(); }
      if (this.data.steps[label].status === "broadcast") { this.data.steps[label].status = "unknown"; await this.save(); } throw new Error(`Transaction ${label} unresolved or failed; inspect journal and reconcile manually.`); }
  }
  async complete(): Promise<void> { this.data.status = "complete"; await this.save(); }
}
export function attemptDir(kind: string): string {
  if (process.env.ATTEMPT_DIR) return resolve(process.env.ATTEMPT_DIR);
  return resolve(fileURLToPath(new URL(`../../../shared/deployments/attempt-${kind}`, import.meta.url)));
}
