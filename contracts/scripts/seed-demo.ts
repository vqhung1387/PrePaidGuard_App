import { network } from "hardhat";
import { access, writeFile } from "node:fs/promises";
import { parseEther, type JsonRpcProvider, type TransactionResponse } from "ethers";
import { address, Attempt, attemptDir, manifestPath, positiveUint256, readManifest, validateChain, verifyDeployment } from "./lib/deployment.js";
async function main() {
  const { ethers } = await network.create(); const chainId = Number((await ethers.provider.getNetwork()).chainId);
  validateChain(chainId); const m = await readManifest(chainId); await verifyDeployment(ethers.provider as unknown as JsonRpcProvider, m);
  const signers = await ethers.getSigners(); const [funder] = signers;
  const merchant = address(process.env.MERCHANT_ADDRESS ?? (chainId === 31337 ? signers[1]?.address : undefined), "merchant");
  const subscriber = address(process.env.SUBSCRIBER_ADDRESS ?? (chainId === 31337 ? signers[2]?.address : undefined), "subscriber");
  if (new Set([merchant, subscriber, address(funder.address, "funder")]).size !== 3 || address(funder.address, "funder") !== address(m.deployer_address, "deployer")) throw new Error("Invalid demo wallets or funder.");
  const token = await ethers.getContractAt("MockUSDC", m.token.address);
  const required = parseEther(chainId === 43113 ? "0.1" : "1");
  const balances = await Promise.all([merchant, subscriber].map((w) => ethers.provider.getBalance(w)));
  const topups = balances.map((b) => b < required ? required - b : 0n); const current = await token.balanceOf(subscriber); const amount = current < 500_000_000n ? 500_000_000n - current : 0n;
  const budget = process.env.GAS_BUDGET_WEI ? positiveUint256(process.env.GAS_BUDGET_WEI) : 0n;
  if (chainId === 43113 && budget === 0n) throw new Error("Set GAS_BUDGET_WEI for seed transactions.");
  if (await ethers.provider.getBalance(funder.address) < topups[0] + topups[1] + budget) throw new Error("Insufficient balance for topups and declared gas budget.");
  const evidencePath = process.env.SEED_EVIDENCE_PATH ?? (manifestPath(chainId).replace(/\.json$/i, "") + ".seed.json");
  try { await access(evidencePath); throw new Error("Seed evidence already exists."); } catch (e) { if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e; }
  const attempt = await Attempt.create(attemptDir("seed"), { deployment_id: m.deployment_id, chain_id: chainId, funder: funder.address, merchant, subscriber, topups_wei: topups.map(String), token_amount: amount.toString(), gas_budget_wei: budget.toString() });
  for (let i = 0; i < 2; i++) if (topups[i] > 0n) await attempt.run(i === 0 ? "merchant_gas" : "subscriber_gas", () => funder.sendTransaction({ to: [merchant, subscriber][i], value: topups[i] }), m.confirmations);
  if (amount > 0n) await attempt.run("subscriber_token", () => token.mint(subscriber, amount) as Promise<TransactionResponse>, m.confirmations);
  const evidence = { deployment_id: m.deployment_id, chain_id: chainId, merchant, subscriber, funding_tx_hashes: Object.values(attempt.data.steps).map((s) => s.hash), next: "Use these wallets to publish a plan, subscribe twice, release one period and refund the other after its grace period." };
  await writeFile(evidencePath, JSON.stringify(evidence, null, 2) + "\n", { flag: "wx" }); await attempt.complete(); console.log(JSON.stringify(evidence));
}
main().catch(() => { console.error("Seed stopped. Inspect the public attempt journal and reconcile manually before another attempt."); process.exitCode = 1; });
