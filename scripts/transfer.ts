import { createWalletClient, createPublicClient, http, parseUnits } from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { readFileSync } from "fs";
import "dotenv/config";

const CONTRACT_ADDRESS = "0x1a23094027e313f6ffa4844dfd892c3d21594f28";

const ABI = [
  {
    "inputs": [{"internalType": "address","name": "to","type": "address"},{"internalType": "uint256","name": "value","type": "uint256"}],
    "name": "transfer",
    "outputs": [{"internalType": "bool","name": "","type": "bool"}],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [{"internalType": "address","name": "account","type": "address"}],
    "name": "balanceOf",
    "outputs": [{"internalType": "uint256","name": "","type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  }
];

async function main() {
  const account = privateKeyToAccount(`0x${process.env.PRIVATE_KEY}`);

  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(process.env.SEPOLIA_RPC)
  });

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(process.env.SEPOLIA_RPC)
  });

  // Check your balance first
  const balance = await publicClient.readContract({
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: "balanceOf",
    args: [account.address]
  });

  console.log(`💰 Your USDT balance: ${Number(balance) / 10**6} USDT`);

  // CHANGE THIS to the address you want to send to
  const RECIPIENT = "0xa148347079Ad18f7be316Bed2B2FA7345fD9CD9B";
  const AMOUNT = parseUnits("100", 6); // 100 USDT (6 decimals)

  console.log(`🚀 Sending 100 USDT to ${RECIPIENT}...`);

  const hash = await walletClient.writeContract({
    address: CONTRACT_ADDRESS,
    abi: ABI,
    functionName: "transfer",
    args: [RECIPIENT, AMOUNT]
  });

  console.log(`✅ Transfer sent! Hash: ${hash}`);
  console.log(`🔍 https://sepolia.etherscan.io/tx/${hash}`);
}

main().catch(console.error);
