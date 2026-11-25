// Generated from ../contracts/out/VaultMigrator.sol/VaultMigrator.json by scripts/generate-abis.mjs.
// Deployed-build fragments in scripts/deployed-patch.json are merged for chain 1301.
// Do not edit by hand.

export const VaultMigratorAbi = [
  {
    "type": "function",
    "name": "migrate",
    "inputs": [
      {
        "name": "fromVault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "toVault",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "newShares",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "Migrated",
    "inputs": [
      {
        "name": "lp",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "fromVault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "toVault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "shares",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "amount0",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "amount1",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "AddressEmptyCode",
    "inputs": [
      {
        "name": "target",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "AddressInsufficientBalance",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "FailedInnerCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NothingToMigrate",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SafeERC20FailedOperation",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "SameVault",
    "inputs": []
  }
] as const;
