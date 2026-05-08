import { configVariable, defineConfig } from "hardhat/config";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import hardhatKeystore from "@nomicfoundation/hardhat-keystore";

export default defineConfig({
  // 1. Register Plugins
  plugins: [hardhatVerify, hardhatKeystore],

  // 2. Compiler Settings
  solidity: "0.8.28",

  // 3. Network Configuration
  networks: {
    sepolia: {
      type: "http",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
    bsc: {
      type: "http",
      url: "https://bsc-dataseed1.defibit.io/",
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
      chainId: 56,
    },
  },

  // 4. Verification Settings
  verify: {
    etherscan: {
      apiKey: configVariable("ETHERSCAN_API_KEY"),
    },
  },
});
