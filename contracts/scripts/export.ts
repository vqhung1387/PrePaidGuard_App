import { artifacts } from "hardhat";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { TypedDataEncoder, Wallet } from "ethers";
import { checkInTypes } from "./signing.js";

const shared = fileURLToPath(new URL("../../shared/", import.meta.url));
const contracts = ["PrepaidVault", "MockUSDC", "MockYieldAdapter"];
await mkdir(shared + "/abi", { recursive: true });
for (const name of contracts) {
  const artifact = await artifacts.readArtifact(name);
  await writeFile(shared + "/abi/" + name + ".json", JSON.stringify(artifact.abi, null, 2) + "\n");
}
const domain = {
  name: "PrepaidGuard", version: "1", chainId: 43113,
  verifyingContract: "0x4444444444444444444444444444444444444444",
};
const message = {
  subscriptionId: "1", merchant: "0x5555555555555555555555555555555555555555",
  periodIndex: "1", nonce: "0", deadline: "1800000000",
};
// Public test vector only. Never use this deterministic wallet for a deployment.
const signer = new Wallet("0x" + "01".padStart(64, "0"));
const fixture = {
  purpose: "TEST VECTOR ONLY; placeholder deployment, fixed test signer",
  domain, types: checkInTypes, primaryType: "CheckIn", message,
  signer: signer.address,
  domainSeparator: TypedDataEncoder.hashDomain(domain),
  structHash: TypedDataEncoder.hashStruct("CheckIn", checkInTypes, message),
  digest: TypedDataEncoder.hash(domain, checkInTypes, message),
  signature: await signer.signTypedData(domain, checkInTypes, message),
};
await writeFile(shared + "/check-in.types.json", JSON.stringify(checkInTypes, null, 2) + "\n");
await writeFile(shared + "/check-in.fixture.json", JSON.stringify(fixture, null, 2) + "\n");
const uint = { type: "string", pattern: "^[0-9]{1,78}$" };
const address = { type: "string", pattern: "^0x[0-9a-fA-F]{40}$" };
const schema = {
  $schema: "https://json-schema.org/draft/2020-12/schema", title: "PrePaidGuard CheckIn QR",
  type: "object", additionalProperties: false,
  required: ["version", "kind", "chainId", "verifyingContract", "message", "signature"],
  properties: {
    version: { const: 1 }, kind: { const: "PREPAIDGUARD_CHECK_IN" },
    chainId: { type: "integer", minimum: 1 }, verifyingContract: address,
    message: {
      type: "object", additionalProperties: false,
      required: checkInTypes.CheckIn.map((field) => field.name),
      properties: { subscriptionId: uint, merchant: address, periodIndex: uint, nonce: uint, deadline: uint },
    },
    signature: { type: "string", pattern: "^0x[0-9a-fA-F]{130}$" },
  },
};
await writeFile(shared + "/check-in.schema.json", JSON.stringify(schema, null, 2) + "\n");
console.log("Exported demo ABIs, CheckIn field types, QR schema and deterministic signing vector.");
