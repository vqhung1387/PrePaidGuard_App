import { artifacts, network } from "hardhat";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { keccak256, toUtf8Bytes, ZeroAddress, type JsonRpcProvider, type TransactionResponse } from "ethers";
import { address, Attempt, attemptDir, manifestPath, requireGasBudget, validateChain, verifyDeployment, type Manifest } from "./lib/deployment.js";

async function main() {
  const { ethers } = await network.create(); const chainId = Number((await ethers.provider.getNetwork()).chainId);
  validateChain(chainId);
  const [deployer] = await ethers.getSigners(); const treasury = address(process.env.TREASURY_ADDRESS ?? (chainId === 31337 ? deployer.address : undefined), "treasury");
  await requireGasBudget(ethers.provider, chainId, deployer.address);
  const mode = process.env.YIELD_MODE ?? "MOCK"; if (!["MOCK", "DISABLED"].includes(mode)) throw new Error("Invalid mode.");
  const output = manifestPath(chainId); try { await access(output); throw new Error("Manifest exists; choose a new output path."); } catch (e) { if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e; }
  const repoRoot = fileURLToPath(new URL("../../", import.meta.url));
  let sourceCommit: string; try { sourceCommit = execFileSync("git", ["-C", repoRoot, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(); } catch { throw new Error("Source commit unavailable."); }
  const dirty = execFileSync("git", ["-C", repoRoot, "status", "--porcelain", "--", "contracts/contracts", "contracts/hardhat.config.ts", "contracts/package-lock.json"], { encoding: "utf8" }).trim() !== "";
  if (chainId === 43113 && dirty) throw new Error("Freeze contract source and compiler configuration before Fuji deployment.");
  const shared = fileURLToPath(new URL("../../shared/", import.meta.url)); const checksums: Record<string, string> = {}; const buildInfo: Record<string, { id: string; hash: string }> = {}; let compilerInfo: unknown;
  for (const name of ["PrepaidVault", "MockUSDC", "MockYieldAdapter"]) { const artifact = await artifacts.readArtifact(name); const json = JSON.stringify(artifact.abi, null, 2) + "\n"; checksums[name] = keccak256(toUtf8Bytes(json)); if (!artifact.buildInfoId) throw new Error("Build info missing."); const raw = await readFile(fileURLToPath(new URL(`../artifacts/build-info/${artifact.buildInfoId}.json`, import.meta.url))); const build = JSON.parse(raw.toString()); buildInfo[name] = { id: artifact.buildInfoId, hash: keccak256(raw) }; if (name === "PrepaidVault") compilerInfo = { version: build.solcVersion, longVersion: build.solcLongVersion, settings: build.input.settings }; }
  const confirmations = chainId === 43113 ? 2 : 1;
  const attempt = await Attempt.create(attemptDir("deploy"), { chain_id: chainId, deployer: deployer.address, treasury, mode, source_commit: sourceCommit, source_dirty: dirty, compiler: compilerInfo, build_info: buildInfo, abi_keccak256: checksums });
  async function deploy(label: string, name: string, args: unknown[]) {
    const factory = await ethers.getContractFactory(name);
    const receipt = await attempt.run(label, async () => { const c = await factory.deploy(...args); return c.deploymentTransaction() as TransactionResponse; }, confirmations);
    if (!receipt.contractAddress) throw new Error("Deployment address missing."); return receipt.contractAddress;
  }
  const token = await deploy("token", "MockUSDC", [deployer.address]);
  const adapter = mode === "MOCK" ? await deploy("adapter", "MockYieldAdapter", [token, deployer.address]) : ZeroAddress;
  const vault = await deploy("vault", "PrepaidVault", [token, treasury, adapter]);
  if (mode === "MOCK") { const contract = await ethers.getContractAt("MockYieldAdapter", adapter); await attempt.run("bind", () => contract.bindVault(vault) as Promise<TransactionResponse>, confirmations); }
  const v = attempt.data.steps.vault;
  const manifest = { deployment_id: `${chainId}-${vault.toLowerCase()}`, chain_id: chainId, chain_name: chainId === 43113 ? "Avalanche Fuji" : "Local Hardhat", public_rpc_url: chainId === 43113 ? "https://api.avax-test.network/ext/bc/C/rpc" : new URL(process.env.RPC_URL ?? "http://127.0.0.1:8545").origin, explorer_url: chainId === 43113 ? "https://testnet.snowtrace.io" : "http://127.0.0.1:8545", vault_address: vault, token: { address: token, symbol: "mUSDC", decimals: 6 }, adapter_address: adapter, treasury_address: treasury, deployer_address: deployer.address, abi_version: "prepaidguard-1", deployment_block: v.blockNumber!, deployment_tx_hash: v.hash!, yield_mode: mode, confirmations, subscription_status_codes: { active: 1, completed: 2, refunded: 3 }, compiler: "0.8.28", vault_code_hash: keccak256(await ethers.provider.getCode(vault)), evidence: { steps: attempt.data.steps, source_commit: sourceCommit, source_dirty: dirty, compiler_settings: compilerInfo, build_info: buildInfo, constructor_args: { token: [deployer.address], adapter: mode === "MOCK" ? [token, deployer.address] : null, vault: [token, treasury, adapter] }, abi_keccak256: checksums, local_artifact_verification: "LOCAL_ARTIFACT_MATCH", source_verification: "NOT_VERIFIED" } };
  await verifyDeployment(ethers.provider as unknown as JsonRpcProvider, manifest as Manifest);
  await mkdir(resolve(shared, "abi"), { recursive: true });
  for (const name of Object.keys(checksums)) { const artifact = await artifacts.readArtifact(name); await writeFile(resolve(shared, "abi", `${name}.json`), JSON.stringify(artifact.abi, null, 2) + "\n"); }
  await mkdir(dirname(output), { recursive: true }); await writeFile(output, JSON.stringify(manifest, null, 2) + "\n", { flag: "wx" }); await attempt.complete();
  console.log(JSON.stringify({ deployment_id: manifest.deployment_id, manifest: output, local_artifact_verification: "LOCAL_ARTIFACT_MATCH", source_verification: "NOT_VERIFIED" }));
}
main().catch(() => { console.error("Deploy stopped. Inspect the public attempt journal and reconcile manually before another attempt; source verification remains required."); process.exitCode = 1; });
