import { createPublicClient, http, formatUnits } from "viem";
import { bsc } from "viem/chains";

const STAKING_ADDRESS = '0x4b62efee5695ed55cd362a0b818f4c5f9694322b' as const;
const POOL_ADDRESS    = '0xb233cf74b14abf9d9702d585c540030125599579' as const;

const STAKING_ABI = [
  { name: 'getBnbPrice', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

const POOL_ABI = [
  { name: 'poolBalance', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

const client = createPublicClient({ chain: bsc, transport: http('https://bsc-dataseed1.defibit.io/') });

async function main() {
  console.log('Checking contracts on BNB mainnet...\n');

  const stakingCode = await client.getBytecode({ address: STAKING_ADDRESS });
  console.log('Staking contract:', stakingCode ? '✅ Deployed' : '❌ NOT FOUND');

  const poolCode = await client.getBytecode({ address: POOL_ADDRESS });
  console.log('Pool contract:   ', poolCode ? '✅ Deployed' : '❌ NOT FOUND');

  try {
    const bnbPrice = await client.readContract({ address: STAKING_ADDRESS, abi: STAKING_ABI, functionName: 'getBnbPrice' });
    console.log('BNB Price:       ', `$${(Number(bnbPrice) / 1e8).toFixed(2)} ✅`);
  } catch (e: any) {
    console.log('BNB Price:        ❌', e.message);
  }

  try {
    const pool = await client.readContract({ address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'poolBalance' });
    console.log('Pool Balance:    ', `${formatUnits(pool as bigint, 18)} WOLV ✅`);
  } catch (e: any) {
    console.log('Pool Balance:     ❌', e.message);
  }
}

main().catch(console.error);
