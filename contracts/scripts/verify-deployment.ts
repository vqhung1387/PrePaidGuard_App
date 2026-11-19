import { readManifest, readProvider, verifyDeployment } from "./lib/deployment.js";
async function main() {
  const { provider, chainId } = readProvider(); if (Number((await provider.getNetwork()).chainId) !== chainId) throw new Error("RPC chain mismatch.");
  const manifest = await readManifest(chainId); await verifyDeployment(provider, manifest);
  console.log(JSON.stringify({ deployment_id: manifest.deployment_id, chain_id: chainId, operational_checks: "pass", local_artifact_verification: manifest.evidence?.build_info && manifest.evidence?.constructor_args && manifest.evidence?.abi_keccak256 ? "LOCAL_ARTIFACT_MATCH" : "NOT_CHECKED", source_verification: "NOT_VERIFIED", reason: "Runtime fingerprint does not prove source correspondence; independent source verification is required." }, null, 2));
}
main().catch(() => { console.error("Deployment verification failed or is incomplete. Check manifest, chain, receipts, confirmations, code and configuration."); process.exitCode = 1; });
