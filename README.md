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
| LindblabUSDT v3 | `0x5E850eFe2843AD0699D6153F03859a5C761ae125` |
| LindblabUSDC v3 | `0xcd690504a5ca7fe44CF1aF3A692fF2FFd828EFcC` |

---

## Notes

- PYCO is the native token of the entire Lindblad network regardless of which chain the bridge deposit originates from.
- Bridge contracts accept USDT/USDC deposits, verify P-256 ECDSA signatures from certified hardware nodes, and release funds on withdrawal.
- Exit fee: 0.1% in PYCO — 50% burned permanently, 50% distributed to active node operators.

---

*Lindblad Protocol — The hardware decides. The physics guarantees. The chain records.*
