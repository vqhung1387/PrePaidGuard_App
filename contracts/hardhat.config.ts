import { configVariable, defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatMocha from "@nomicfoundation/hardhat-mocha";
import hardhatEthersChaiMatchers from "@nomicfoundation/hardhat-ethers-chai-matchers";

export default defineConfig({
  plugins: [hardhatEthers, hardhatMocha, hardhatEthersChaiMatchers],
  solidity: {
    version: "0.8.28",
    settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "cancun" },
  },
  networks: {
    default: { type: "edr-simulated", chainType: "l1", chainId: 31337 },
    node: {
      type: "edr-simulated", chainType: "l1", chainId: 31337,
      throwOnTransactionFailures: false,
    },
    localhost: { type: "http", chainType: "l1", url: "http://127.0.0.1:8545" },
    fuji: {
      type: "http",
      chainType: "l1",
      chainId: 43113,
      url: process.env.FUJI_RPC_URL ?? "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [configVariable("DEPLOYER_PRIVATE_KEY")],
    },
  },
});
