import { network } from "hardhat";
import { type JsonRpcProvider, type TransactionResponse } from "ethers";
import { address, Attempt, attemptDir, positiveUint256, requireGasBudget, readManifest, validateChain, verifyDeployment } from "./lib/deployment.js";
async function main() {
  const id = positiveUint256(process.env.SUBSCRIPTION_ID ?? ""); const amount = positiveUint256(process.env.YIELD_AMOUNT ?? "");
  const { ethers } = await network.create(); const chainId = Number((await ethers.provider.getNetwork()).chainId);
  validateChain(chainId); const m = await readManifest(chainId); if (m.yield_mode !== "MOCK") throw new Error("MOCK deployment required.");
  await verifyDeployment(ethers.provider as unknown as JsonRpcProvider, m);
  const [funder] = await ethers.getSigners(); await requireGasBudget(ethers.provider, chainId, funder.address); if (address(funder.address, "funder") !== address(m.deployer_address, "deployer")) throw new Error("Wrong funder.");
  const token = await ethers.getContractAt("MockUSDC", m.token.address); const adapter = await ethers.getContractAt("MockYieldAdapter", m.adapter_address); const vault = await ethers.getContractAt("PrepaidVault", m.vault_address);
  const position = await vault.getSubscription(id); const principal = await adapter.principalOf(id);
  if (Number(position.status) !== 1 || position.remainingPrincipal === 0n || principal !== position.remainingPrincipal) throw new Error("Active backed position required.");
  const attempt = await Attempt.create(attemptDir("yield"), { deployment_id: m.deployment_id, chain_id: chainId, funder: funder.address, subscription_id: id.toString(), amount: amount.toString() });
  await attempt.run("mint", () => token.mint(funder.address, amount) as Promise<TransactionResponse>, m.confirmations);
  await attempt.run("approve", () => token.approve(m.adapter_address, amount) as Promise<TransactionResponse>, m.confirmations);
  await attempt.run("fund", () => adapter.fundYield(id, amount) as Promise<TransactionResponse>, m.confirmations);
  await attempt.complete(); console.log(JSON.stringify({ subscriptionId: id.toString(), amount: amount.toString(), steps: attempt.data.steps }));
}
main().catch(() => { console.error("Yield funding stopped. Inspect the public attempt journal and reconcile manually; do not repeat an uncertain funding transaction."); process.exitCode = 1; });
