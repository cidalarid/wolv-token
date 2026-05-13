import { configVariable, defineConfig } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import hardhatKeystore from "@nomicfoundation/hardhat-keystore";

export default defineConfig({
  plugins: [hardhatVerify, hardhatKeystore],
  solidity: "0.8.28",
  networks: {
    sepolia: {
      type: "http",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      gas: 5000000,
      gasPrice: 20000000000,
    },
    bsc: {
      type: "http",
      url: "https://bsc-dataseed1.defibit.io/",
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      chainId: 56,
    },
    bscTestnet: {
      type: "http",
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      chainId: 97,
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
});
