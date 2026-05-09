import { createWalletClient, createPublicClient, http, Address } from "viem";
import { bsc } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import hre from "hardhat";

// ── Artifacts ───────────────────────────────────────────────────────────────
// Ensure paths are correct relative to where you run the script
const wolvArtifact = JSON.parse(
  readFileSync("./artifacts/contracts/WOLV_v2.sol/WOLV.json", "utf8"),
);
const poolArtifact = JSON.parse(
  readFileSync("./artifacts/contracts/RewardPool.sol/RewardPool.json", "utf8"),
);
const stakingArtifact = JSON.parse(
  readFileSync(
    "./artifacts/contracts/StakingContract.sol/StakingContract.json",
    "utf8",
  ),
);

// ── Addresses ────────────────────────────────────────────────────────────────
const TREASURY: Address = "0x023e3ff33fdf653e1617c8aad0a907e9a6df5456";
const MULTISIG: Address = "0x023e3ff33fdf653e1617c8aad0a907e9a6df5456";
const BUSD_BSC: Address = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const CHAINLINK_BNB_USD: Address = "0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE";

/**
 * Helper to deploy contracts and wait for confirmation
 */
async function deploy(
  walletClient: any,
  publicClient: any,
  label: string,
  abi: any[],
  bytecode: string,
  args: any[],
): Promise<Address> {
  console.log(`\nDeploying ${label}...`);

  const hash = await walletClient.deployContract({
    abi,
    bytecode: (bytecode.startsWith("0x")
      ? bytecode
      : `0x${bytecode}`) as `0x${string}`,
    args,
  });

  console.log(`  Transaction Hash: ${hash}`);

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
    confirmations: 2, // 3 can sometimes timeout on busy networks, 2 is usually safe
    timeout: 180_000,
  });

  if (receipt.status === "reverted")
    throw new Error(`${label} deployment reverted`);

  console.log(`  ✅ ${label} deployed at: ${receipt.contractAddress}`);
  return receipt.contractAddress as Address;
}

async function main() {
  // ── Setup Configuration ───────────────────────────────────────────────────
  // We pull the URL from the Hardhat network config directly
  const networkConfig = hre.config.networks.bsc as {
    accounts: Array<{ get: () => Promise<string> }>;
    url: { getUrl: () => Promise<string> };
  };
  const rawKey = await networkConfig.accounts[0].get();
  const rpcUrl = await networkConfig.url.getUrl();
  const privateKey = (
    rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`
  ) as `0x${string}`;

  const account = privateKeyToAccount(privateKey);
  const walletClient = createWalletClient({
    account,
    chain: bsc,
    transport: http(rpcUrl),
  });
  const publicClient = createPublicClient({
    chain: bsc,
    transport: http(rpcUrl),
  });

  console.log(`🚀 Starting deployment on ${hre.network.name}`);
  console.log(`Deploying from: ${account.address}`);

  // ── 1. Deploy WOLV Token ───────────────────────────────────────────────────
  const wolvAddress = await deploy(
    walletClient,
    publicClient,
    "WOLV Token",
    wolvArtifact.abi,
    wolvArtifact.bytecode,
    [TREASURY, MULTISIG],
  );

  // ── 2. Deploy RewardPool ───────────────────────────────────────────────────
  const poolAddress = await deploy(
    walletClient,
    publicClient,
    "RewardPool",
    poolArtifact.abi,
    poolArtifact.bytecode,
    [wolvAddress, TREASURY, MULTISIG],
  );

  // ── 3. Deploy StakingContract ──────────────────────────────────────────────
  const stakingAddress = await deploy(
    walletClient,
    publicClient,
    "StakingContract",
    stakingArtifact.abi,
    stakingArtifact.bytecode,
    [MULTISIG, BUSD_BSC, poolAddress, CHAINLINK_BNB_USD],
  );

  // ── 4. Link StakingContract → RewardPool ──────────────────────────────────
  console.log("\nLinking StakingContract to RewardPool...");
  const linkHash = await walletClient.writeContract({
    address: poolAddress,
    abi: poolArtifact.abi,
    functionName: "setStakingContract",
    args: [stakingAddress],
  });

  await publicClient.waitForTransactionReceipt({
    hash: linkHash,
    confirmations: 2,
  });
  console.log("✅ Linked successfully");

  // ── Summary ────────────────────────────────────────────────────────────────
  console.log("\n════════════════════════════════════════");
  console.log("WOLV Token:      ", wolvAddress);
  console.log("RewardPool:      ", poolAddress);
  console.log("StakingContract: ", stakingAddress);
  console.log("════════════════════════════════════════\n");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
