// Generated from ../contracts/out/StrategyRegistry.sol/StrategyRegistry.json by scripts/generate-abis.mjs.
// Deployed-build fragments in scripts/deployed-patch.json are merged for chain 1301.
// Do not edit by hand.

export const StrategyRegistryAbi = [
  {
    "type": "constructor",
    "inputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "ALPHA_LOOKBACK",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "CHECKPOINT_INTERVAL",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "LOOSEN_DELAY",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_CHECKPOINTS",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "MAX_LEADERBOARD_PAGE",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "alphaAccumulator",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "alphaSamples",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "applyLoosenEnvelope",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "checkpointAlpha",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "cumulativeAlpha",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "factory",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAlpha",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCurator",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getEnvelope",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isCurator",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "who",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "leaderboard",
    "inputs": [
      {
        "name": "limit",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "ids",
        "type": "uint256[]",
        "internalType": "uint256[]"
      },
      {
        "name": "scores",
        "type": "int256[]",
        "internalType": "int256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "leaderboardPage",
    "inputs": [
      {
        "name": "offset",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "limit",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "ids",
        "type": "uint256[]",
        "internalType": "uint256[]"
      },
      {
        "name": "scores",
        "type": "int256[]",
        "internalType": "int256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "nextStrategyId",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "owner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "pendingEnvelope",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "envelope",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      },
      {
        "name": "unlockTime",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "queueLoosenEnvelope",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "newEnv",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "rankedCount",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "registerStrategy",
    "inputs": [
      {
        "name": "env",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "outputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setFactory",
    "inputs": [
      {
        "name": "_factory",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setStrategyVault",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "strategies",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "curator",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "envelope",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      },
      {
        "name": "active",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "strategyVault",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "tightenEnvelope",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "newEnv",
        "type": "tuple",
        "internalType": "struct Envelope",
        "components": [
          {
            "name": "maxRangeWidth",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxCenterShift",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxTwapDistanceTicks",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "minRebalanceInterval",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxPriceImpactBps",
            "type": "uint32",
            "internalType": "uint32"
          },
          {
            "name": "maxNavLossBps",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "maxDailyNavLossBps",
            "type": "uint32",
            "internalType": "uint32"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "AlphaCheckpointed",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "cumulativeAlpha",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EnvelopeLooseningApplied",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EnvelopeLooseningQueued",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "unlockTime",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EnvelopeTightened",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "FactorySet",
    "inputs": [
      {
        "name": "factory",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StrategyRegistered",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "curator",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "StrategyVaultBound",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "FactoryAlreadySet",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidParams",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NavLossFloorTooLow",
    "inputs": [
      {
        "name": "floor",
        "type": "int24",
        "internalType": "int24"
      },
      {
        "name": "minFloor",
        "type": "int24",
        "internalType": "int24"
      }
    ]
  },
  {
    "type": "error",
    "name": "NoPendingChange",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotTighter",
    "inputs": []
  },
  {
    "type": "error",
    "name": "StrategyAlreadyBound",
    "inputs": []
  },
  {
    "type": "error",
    "name": "TimelockNotReady",
    "inputs": []
  },
  {
    "type": "error",
    "name": "Unauthorized",
    "inputs": []
  },
  {
    "type": "error",
    "name": "UnknownStrategy",
    "inputs": []
  }
] as const;
