import { network } from "hardhat";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { ZeroAddress } from "ethers";

const { ethers } = await network.create();
const chainId = Number((await ethers.provider.getNetwork()).chainId);
if (![31337, 43113].includes(chainId)) throw new Error("Only local and Fuji are supported.");
const subscriptionId = process.env.SUBSCRIPTION_ID ?? "";
const amount = process.env.YIELD_AMOUNT ?? "";
if (!/^[1-9][0-9]{0,77}$/.test(subscriptionId) || !/^[1-9][0-9]{0,77}$/.test(amount)) {
  throw new Error("Set SUBSCRIPTION_ID and YIELD_AMOUNT to positive atomic-unit integer strings.");
}
const filename = chainId === 43113 ? "fuji.json" : "local.json";
const manifest = JSON.parse(await readFile(fileURLToPath(new URL("../../shared/deployments/" + filename, import.meta.url)), "utf8"));
if (manifest.chain_id !== chainId || manifest.yield_mode !== "MOCK" || manifest.adapter_address === ZeroAddress) {
  throw new Error("Manifest must describe a MOCK deployment on this chain.");
}
const [funder] = await ethers.getSigners();
const token = await ethers.getContractAt("MockUSDC", manifest.token.address);
const adapter = await ethers.getContractAt("MockYieldAdapter", manifest.adapter_address);
if (await adapter.funder() !== funder.address) throw new Error("Use the configured mock funding wallet.");
const confirmations = manifest.confirmations;
const mint = await (await token.mint(funder.address, BigInt(amount))).wait(confirmations);
const approve = await (await token.approve(adapter.target, BigInt(amount))).wait(confirmations);
const funded = await (await adapter.fundYield(BigInt(subscriptionId), BigInt(amount))).wait(confirmations);
console.log(JSON.stringify({ subscriptionId, amount, mint: mint!.hash, approve: approve!.hash, funded: funded!.hash }));
