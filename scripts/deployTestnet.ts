import { createWalletClient, createPublicClient, http } from "viem";
import { bscTestnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import hre from "hardhat";

// Load artifacts
const wolvArtifact    = JSON.parse(readFileSync("./artifacts/contracts/WOLV.sol/WOLV.json", "utf8"));
const poolArtifact    = JSON.parse(readFileSync("./artifacts/contracts/RewardPool.sol/RewardPool.json", "utf8"));
const stakingArtifact = JSON.parse(readFileSync("./artifacts/contracts/StakingContract.sol/StakingContract.json", "utf8"));

async function main() {
  const networkConfig = hre.config.networks.bscTestnet as {
    accounts: Array<{ get: () => Promise<string> }>;
    url: { getUrl: () => Promise<string> };
  };

  const rawKey = await networkConfig.accounts[0].get();
  const rpcUrl = await networkConfig.url.getUrl();
  const privateKey = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as `0x${string}`;
  const account = privateKeyToAccount(privateKey);

  const walletClient = createWalletClient({ account, chain: bscTestnet, transport: http(rpcUrl) });
  const publicClient = createPublicClient({ chain: bscTestnet, transport: http(rpcUrl) });

  console.log(`\n🚀 Deploying to BSC Testnet from: ${account.address}\n`);

  // 1. Deploy WOLV token
  console.log("1️⃣  Deploying WOLV token...");
  const wolvHash = await walletClient.deployContract({
    abi: wolvArtifact.abi,
    bytecode: wolvArtifact.bytecode as `0x${string}`,
    args: [],
  });
  const wolvReceipt = await publicClient.waitForTransactionReceipt({ hash: wolvHash, confirmations: 3 });
  if (wolvReceipt.status === "reverted") throw new Error("WOLV deploy reverted");
  const wolvAddress = wolvReceipt.contractAddress!;
  console.log(`   ✅ WOLV deployed at: ${wolvAddress}`);

  // 2. Deploy RewardPool with WOLV address
  console.log("\n2️⃣  Deploying RewardPool...");
  const poolHash = await walletClient.deployContract({
    abi: poolArtifact.abi,
    bytecode: poolArtifact.bytecode as `0x${string}`,
    args: [wolvAddress],
  });
  const poolReceipt = await publicClient.waitForTransactionReceipt({ hash: poolHash, confirmations: 3 });
  if (poolReceipt.status === "reverted") throw new Error("RewardPool deploy reverted");
  const poolAddress = poolReceipt.contractAddress!;
  console.log(`   ✅ RewardPool deployed at: ${poolAddress}`);

  // 3. Deploy StakingContract with WOLV + Pool addresses
  console.log("\n3️⃣  Deploying StakingContract...");
  const stakingHash = await walletClient.deployContract({
    abi: stakingArtifact.abi,
    bytecode: stakingArtifact.bytecode as `0x${string}`,
    args: [wolvAddress, poolAddress],
  });
  const stakingReceipt = await publicClient.waitForTransactionReceipt({ hash: stakingHash, confirmations: 3 });
  if (stakingReceipt.status === "reverted") throw new Error("StakingContract deploy reverted");
  const stakingAddress = stakingReceipt.contractAddress!;
  console.log(`   ✅ StakingContract deployed at: ${stakingAddress}`);

  console.log(`
╔══════════════════════════════════════════════════════════════╗
║           BSC TESTNET DEPLOYMENT COMPLETE                    ║
╠══════════════════════════════════════════════════════════════╣
║  WOLV Token     : ${wolvAddress}  ║
║  Reward Pool    : ${poolAddress}  ║
║  Staking        : ${stakingAddress}  ║
╠══════════════════════════════════════════════════════════════╣
║  Update these in your stake/page.tsx for testing             ║
╚══════════════════════════════════════════════════════════════╝
  `);
}

main().catch(console.error);
