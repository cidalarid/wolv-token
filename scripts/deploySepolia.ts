import { createWalletClient, createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import hre from "hardhat";

const wolvArtifact    = JSON.parse(readFileSync("./artifacts/contracts/WOLV.sol/WOLV.json", "utf8"));
const poolArtifact    = JSON.parse(readFileSync("./artifacts/contracts/RewardPool.sol/RewardPool.json", "utf8"));
const stakingArtifact = JSON.parse(readFileSync("./artifacts/contracts/StakingContract.sol/StakingContract.json", "utf8"));

async function main() {
  const networkConfig = hre.config.networks.sepolia as {
    accounts: Array<{ get: () => Promise<string> }>;
    url: { getUrl: () => Promise<string> };
  };

  const rawKey = await networkConfig.accounts[0].get();
  const rpcUrl = await networkConfig.url.getUrl();
  const privateKey = (rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`) as `0x${string}`;
  const account = privateKeyToAccount(privateKey);

  const walletClient = createWalletClient({ account, chain: sepolia, transport: http(rpcUrl) });
  const publicClient = createPublicClient({ chain: sepolia, transport: http(rpcUrl) });

  console.log(`\n🚀 Deploying to Sepolia from: ${account.address}\n`);

  // 1. Deploy WOLV
  console.log("1️⃣  Deploying WOLV token...");
  const wolvHash = await walletClient.deployContract({
    abi: wolvArtifact.abi,
    bytecode: wolvArtifact.bytecode as `0x${string}`,
    args: [],
  });
  const wolvReceipt = await publicClient.waitForTransactionReceipt({ hash: wolvHash, confirmations: 2, timeout: 120_000 });
  if (wolvReceipt.status === "reverted") throw new Error("WOLV deploy reverted");
  const wolvAddress = wolvReceipt.contractAddress!;
  console.log(`   ✅ WOLV:    ${wolvAddress}`);

  // 2. Deploy RewardPool
  console.log("\n2️⃣  Deploying RewardPool...");
  const poolHash = await walletClient.deployContract({
    abi: poolArtifact.abi,
    bytecode: poolArtifact.bytecode as `0x${string}`,
    args: [wolvAddress],
  });
  const poolReceipt = await publicClient.waitForTransactionReceipt({ hash: poolHash, confirmations: 2, timeout: 120_000 });
  if (poolReceipt.status === "reverted") throw new Error("RewardPool deploy reverted");
  const poolAddress = poolReceipt.contractAddress!;
  console.log(`   ✅ Pool:    ${poolAddress}`);

  // 3. Deploy StakingContract
  console.log("\n3️⃣  Deploying StakingContract...");
  const stakingHash = await walletClient.deployContract({
    abi: stakingArtifact.abi,
    bytecode: stakingArtifact.bytecode as `0x${string}`,
    args: [wolvAddress, poolAddress],
  });
  const stakingReceipt = await publicClient.waitForTransactionReceipt({ hash: stakingHash, confirmations: 2, timeout: 120_000 });
  if (stakingReceipt.status === "reverted") throw new Error("StakingContract deploy reverted");
  const stakingAddress = stakingReceipt.contractAddress!;
  console.log(`   ✅ Staking: ${stakingAddress}`);

  console.log(`
╔════════════════════════════════════════════════════════════════╗
║            SEPOLIA DEPLOYMENT COMPLETE                         ║
╠════════════════════════════════════════════════════════════════╣
║  WOLV    : ${wolvAddress}  ║
║  Pool    : ${poolAddress}  ║
║  Staking : ${stakingAddress}  ║
╠════════════════════════════════════════════════════════════════╣
║  Update stake/page.tsx with these addresses for testing        ║
╚════════════════════════════════════════════════════════════════╝
  `);
}

main().catch(console.error);
