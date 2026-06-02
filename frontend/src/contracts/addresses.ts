import { sepolia, hardhat } from 'wagmi/chains';

interface ContractAddresses {
  TOKEN_ADDRESS: `0x${string}`;
  TOKEN_BANK_ADDRESS: `0x${string}`;
}

const ADDRESSES: Record<number, ContractAddresses> = {
  [hardhat.id]: {
    TOKEN_ADDRESS: '0x5FbDB2315678afecb367f032d93F642f64180aa3',
    TOKEN_BANK_ADDRESS: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
  },
  [sepolia.id]: {
    TOKEN_ADDRESS: '0x54645eD7Df92a504cb93D2474Fe8E30fC6851867',
    TOKEN_BANK_ADDRESS: '0xcF025458cDC5f042FAbC8CCA39928A8B1204c3F7',
  },
};

export function getAddresses(chainId: number): ContractAddresses {
  return ADDRESSES[chainId] ?? ADDRESSES[hardhat.id];
}

export const TOKEN_ADDRESS = ADDRESSES[hardhat.id].TOKEN_ADDRESS;
export const TOKEN_BANK_ADDRESS = ADDRESSES[hardhat.id].TOKEN_BANK_ADDRESS;

// MetaMask EIP-7702 Delegator contract (deterministic deployment)
export const DELEGATOR_ADDRESS = '0x63c0c19a282a1B52b07dD5a65b58948A07DAE32B' as const;

// Batch execution mode for ERC-7579 / ERC-7821
export const BATCH_EXECUTION_MODE = '0x0100000000000000000000000000000000000000000000000000000000000000' as const;
