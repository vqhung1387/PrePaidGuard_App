import { network } from "hardhat";
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { getAddress, parseEther } from "ethers";

const { ethers } = await network.create();
const chainId = Number((await ethers.provider.getNetwork()).chainId);
if (![31337, 43113].includes(chainId)) throw new Error("Seed supports only local or Fuji.");
const signers = await ethers.getSigners();
const [funder] = signers;
const merchant = getAddress(process.env.MERCHANT_ADDRESS ?? (chainId === 31337 ? signers[1].address : ""));
const subscriber = getAddress(process.env.SUBSCRIBER_ADDRESS ?? (chainId === 31337 ? signers[2].address : ""));
if (merchant === subscriber || merchant === funder.address || subscriber === funder.address) {
  throw new Error("Use three distinct demo wallets.");
}
const filename = chainId === 43113 ? "fuji.json" : "local.json";
const path = fileURLToPath(new URL("../../shared/deployments/" + filename, import.meta.url));
const manifest = JSON.parse(await readFile(path, "utf8"));
if (manifest.chain_id !== chainId) throw new Error("Manifest chain mismatch.");
const token = await ethers.getContractAt("MockUSDC", manifest.token.address);
if (getAddress(await token.owner()) !== funder.address) throw new Error("Seed requires the token funding wallet.");
const confirmations = manifest.confirmations;
const txs: string[] = [];
for (const wallet of [merchant, subscriber]) {
  const required = parseEther(chainId === 43113 ? "0.1" : "1");
  const balance = await ethers.provider.getBalance(wallet);
  if (balance < required) {
    const receipt = await (await funder.sendTransaction({ to: wallet, value: required - balance })).wait(confirmations);
    txs.push(receipt!.hash);
  }
}
const requiredTokens = 500_000_000n;
const current = await token.balanceOf(subscriber);
if (current < requiredTokens) {
  const receipt = await (await token.mint(subscriber, requiredTokens - current)).wait(confirmations);
  txs.push(receipt!.hash);
}
const evidence = {
  deployment_id: manifest.deployment_id, chain_id: chainId,
  merchant, subscriber, funding_tx_hashes: txs,
  next: "Use these wallets in Flutter to publish a plan, subscribe twice, release one period and refund the other after its grace period.",
};
await writeFile(path.replace(".json", ".seed.json"), JSON.stringify(evidence, null, 2) + "\n");
console.log(JSON.stringify(evidence, null, 2));
