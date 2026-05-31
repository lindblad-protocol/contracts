# Lindblad Protocol — Smart Contracts

Solidity smart contracts for the Lindblad Protocol bridge. Deployed on Arbitrum One and Polygon mainnet.

---

## Arbitrum One (Chain ID: 42161)

| Contract | Address |
|---|---|
| LindblabUSDT v3 | `0x7e0f53f04dDc48dFdc96DFE93606a73f0dCF56A3` |
| LindblabUSDC v3 | `0x1AfC80b30cBBE50E8aBb4585f53ff530c305d416` |
| PYCO ERC-20 | `0x16a69CcdA3865a23537d46055dC6564A2813C36B` |

## Polygon (Chain ID: 137)

| Contract | Address |
|---|---|
| LindblabUSDT v3 | `0x17c6d525A8D809fcBe78aBE4FCaE1F9ddb0b8fa8` |
| LindblabUSDC v3 | `0x9964c63Af739bf8b4702E243f904570b17F33ab4` |

---

## Notes

- PYCO is the native token of the entire Lindblad network regardless of which chain the bridge deposit originates from.
- Bridge contracts accept USDT/USDC deposits, verify P-256 ECDSA signatures from certified hardware nodes, and release funds on withdrawal.
- Exit fee: 0.1% in PYCO — 50% burned permanently, 50% distributed to active node operators.

---

*Lindblad Protocol — The hardware decides. The physics guarantees. The chain records.*
