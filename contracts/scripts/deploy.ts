import { artifacts, network } from "hardhat";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { getAddress, keccak256, ZeroAddress } from "ethers";

const { ethers } = await network.create();
const chainId = Number((await ethers.provider.getNetwork()).chainId);
if (![31337, 43113].includes(chainId)) throw new Error("Deploy supports only local chain 31337 or Fuji 43113.");
const [deployer] = await ethers.getSigners();
const treasury = getAddress(process.env.TREASURY_ADDRESS ?? (chainId === 31337 ? deployer.address : ""));
const mode = process.env.YIELD_MODE ?? "MOCK";
if (treasury === ZeroAddress || !["MOCK", "DISABLED"].includes(mode)) throw new Error("Invalid treasury or YIELD_MODE.");
const confirmations = chainId === 43113 ? 2 : 1;
async function deploy(name: string, args: unknown[]) {
  const contract = await ethers.deployContract(name, args);
  await contract.deploymentTransaction()!.wait(confirmations);
  return contract;
}
const token = await deploy("MockUSDC", [deployer.address]);
const adapter = mode === "MOCK" ? await deploy("MockYieldAdapter", [token.target, deployer.address]) : null;
const vault = await deploy("PrepaidVault", [token.target, treasury, adapter?.target ?? ZeroAddress]);
const receipt = await vault.deploymentTransaction()!.wait(confirmations);
if (!receipt || receipt.status !== 1) throw new Error("Vault deployment failed.");
if (adapter) await (await adapter.bindVault(vault.target)).wait(confirmations);
const shared = fileURLToPath(new URL("../../shared/", import.meta.url));
await mkdir(shared + "/abi", { recursive: true });
await mkdir(shared + "/deployments", { recursive: true });
for (const name of ["PrepaidVault", "MockUSDC", "MockYieldAdapter"]) {
  const artifact = await artifacts.readArtifact(name);
  await writeFile(shared + "/abi/" + name + ".json", JSON.stringify(artifact.abi, null, 2) + "\n");
}
const manifest = {
  deployment_id: chainId + "-" + String(vault.target).toLowerCase(),
  chain_id: chainId, chain_name: chainId === 43113 ? "Avalanche Fuji" : "Local Hardhat",
  public_rpc_url: chainId === 43113 ? "https://api.avax-test.network/ext/bc/C/rpc" : "http://127.0.0.1:8545",
  explorer_url: chainId === 43113 ? "https://testnet.snowtrace.io" : "http://127.0.0.1:8545",
  vault_address: vault.target, token: { address: token.target, symbol: "mUSDC", decimals: 6 },
  adapter_address: adapter?.target ?? ZeroAddress,
  treasury_address: treasury, deployer_address: deployer.address,
  abi_version: "prepaidguard-1", deployment_block: receipt.blockNumber,
  deployment_tx_hash: receipt.hash, yield_mode: mode, confirmations,
  subscription_status_codes: { active: 1, completed: 2, refunded: 3 },
  compiler: "0.8.28", vault_code_hash: keccak256(await ethers.provider.getCode(vault.target)),
};
const filename = chainId === 43113 ? "fuji.json" : "local.json";
await writeFile(shared + "/deployments/" + filename, JSON.stringify(manifest, null, 2) + "\n");
console.log(JSON.stringify(manifest, null, 2));
