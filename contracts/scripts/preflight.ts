import { address, positiveUint256, readProvider } from "./lib/deployment.js";

async function main() {
  const { provider, chainId } = readProvider();
  if (Number((await provider.getNetwork()).chainId) !== chainId) throw new Error("RPC chain mismatch.");
  const deployer = address(process.env.DEPLOYER_ADDRESS, "deployer");
  const treasury = address(process.env.TREASURY_ADDRESS, "treasury");
  const mode = process.env.YIELD_MODE; if (mode !== "MOCK" && mode !== "DISABLED") throw new Error("Set YIELD_MODE to MOCK or DISABLED.");
  const wallets = [deployer];
  for (const key of ["MERCHANT_ADDRESS", "SUBSCRIBER_ADDRESS"]) if (process.env[key]) wallets.push(address(process.env[key], key));
  if (new Set(wallets).size !== wallets.length) throw new Error("Demo wallets must be distinct.");
  const gasBudget = positiveUint256(process.env.GAS_BUDGET_WEI ?? "");
  const topup = process.env.SEED_TOPUP_BUDGET_WEI ? positiveUint256(process.env.SEED_TOPUP_BUDGET_WEI) : 0n;
  const balance = await provider.getBalance(deployer); const total = gasBudget + topup;
  console.log(JSON.stringify({ chain_id: chainId, deployer, treasury, mode, balance_wei: balance.toString(), gas_budget_wei: gasBudget.toString(), seed_topup_budget_wei: topup.toString(), sufficient_for_declared_budget: balance >= total, budget_is_estimate: false }, null, 2));
  if (balance < total) throw new Error("Balance below declared budget.");
}
main().catch(() => { console.error("Preflight failed. Check chain, public addresses, mode, budget and RPC availability."); process.exitCode = 1; });
