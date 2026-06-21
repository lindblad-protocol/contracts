# Lindblad Protocol — Smart Contracts

Solidity smart contracts for the Lindblad Protocol — hardware-attested infrastructure for tokenized real-world assets and autonomous machine-to-machine commerce.

All contracts are deployed and verified on-chain. Source code is open under the MIT License.

---

## Repository contents

| File | Purpose |
|------|---------|
| `LindblabUSDT_v3.sol` | Bridge representation of USDT on the Spectral Ledger |
| `LindblabUSDC_v3.sol` | Bridge representation of USDC on the Spectral Ledger |
| `PYCO.sol` | PYCO native token (ERC-20) |
| `M2MEscrow.sol` | Machine-to-Machine commerce escrow with hardware-attested identity |
| `MockUSDC.sol` | Test ERC-20 (6 decimals) used in testnet M2M demos |

---

## Production deployments

### Arbitrum One (Chain ID: 42161)

| Contract | Address |
|----------|---------|
| LindblabUSDT v3 | `0x7e0f53f04dDc48dFdc96DFE93606a73f0dCF56A3` |
| LindblabUSDC v3 | `0x1AfC80b30cBBE50E8aBb4585f53ff530c305d416` |
| PYCO ERC-20 | `0x16a69CcdA3865a23537d46055dC6564A2813C36B` |

### Polygon (Chain ID: 137)

| Contract | Address |
|----------|---------|
| LindblabUSDT v3 | `0x17c6d525A8D809fcBe78aBE4FCaE1F9ddb0b8fa8` |
| LindblabUSDC v3 | `0x9964c63Af739bf8b4702E243f904570b17F33ab4` |

---

## Testnet deployments

### Arbitrum Sepolia (Chain ID: 421614)

| Contract | Address |
|----------|---------|
| M2MEscrow | `0xdeaED8e809733667D80a8E6ca40A02366598CA60` |
| MockUSDC (test token) | `0xa6Ee2f4248b447f934Aabf44aA534C6C21654F6c` |

### Robinhood Chain Testnet (Chain ID: 46630)

| Contract | Address |
|----------|---------|
| M2MEscrow (mirror) | `0x16a69CcdA3865a23537d46055dC6564A2813C36B` |

---

## How the contracts fit together

### Bridge layer — `LindblabUSDT_v3`, `LindblabUSDC_v3`, `PYCO`

These contracts implement the Lindblad bridge between public chains (Arbitrum One, Polygon) and the Spectral Ledger:

- USDT/USDC deposits are accepted on the public chain.
- Withdrawal requests are signed by certified hardware nodes (P-256 ECDSA from PUF-derived keys).
- The signature is verified on-chain before funds are released.
- A 0.1% exit fee in PYCO applies on withdrawals: 50% burned permanently, 50% distributed to active node operators weighted by their Physical Coherence Verification Score (PCV-4).

PYCO is the native token of the entire Lindblad network regardless of which chain the bridge deposit originates from.

### Application layer — `M2MEscrow`

`M2MEscrow` enforces the lifecycle of an autonomous machine-to-machine transaction:

```
Requested → Accepted → InProgress → Delivered → Settled
                                ↘ Cancelled
```

Each participant must be a registered Lindblad node. The registry maps Ethereum addresses to hardware-attested identities. An address is derived from the node's ECDSA public key:

```
address = keccak256(pubKey[1:])[-20:]
```

The public key itself is derived in real time from the node's SRAM PUF via the BCH(255,139,t=15) fuzzy extractor — never stored, never extractable.

For full architectural details, see the [M2M Commerce section in the protocol docs](https://lindblad.io/docs#m2m-commerce).

### Testing — `MockUSDC`

`MockUSDC` is a 6-decimal ERC-20 token deployed on testnet to exercise the M2M escrow flow without using a wrapped real-USDC. It includes a public faucet (1,000 USDC per address per hour) for demo participants.

---

## Verification on block explorers

- **Arbitrum One:** [Arbiscan](https://arbiscan.io/) — search by contract address
- **Arbitrum Sepolia:** [sepolia.arbiscan.io](https://sepolia.arbiscan.io/) — M2MEscrow and MockUSDC verified
- **Polygon:** [PolygonScan](https://polygonscan.com/)

---

## Local development

Contracts are built with [Hardhat](https://hardhat.org/) and [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/).

```bash
npm install
npx hardhat compile
npx hardhat test
```

Solidity version: `^0.8.24` (Cancun EVM).

---

## Security notes

- Contracts are **not audited** by a third-party firm. Use at your own risk.
- M2MEscrow is in testnet phase. Mainnet deployment will follow community feedback and a formal audit.
- The node registry on M2MEscrow is currently permissioned (controlled by the Lindblad Oracle). Future iterations will support on-chain PUF signature verification for permissionless node registration.
- To report a security issue, please open a private security advisory in this repository.

---

## License

MIT — see SPDX identifier in each `.sol` file.

---

## Links

- Website: [lindblad.io](https://lindblad.io)
- Protocol overview: [lindblad.io/protocol](https://lindblad.io/protocol)
- Documentation: [lindblad.io/docs](https://lindblad.io/docs)
- RWAFi: [lindblad.io/rwafi](https://lindblad.io/rwafi)
- M2M Commerce: [lindblad.io/m2m](https://lindblad.io/m2m)
- API Reference: [github.com/lindblad-protocol/api](https://github.com/lindblad-protocol/api)
- LCP Specification: [github.com/lindblad-protocol/spec](https://github.com/lindblad-protocol/spec)

---

*Lindblad Protocol — The hardware decides. The physics guarantees. The chain records.*
