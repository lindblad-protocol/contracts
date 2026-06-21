// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice Test ERC-20 token mimicking USDC (6 decimals) for Lindblad M2M Escrow testing.
 * @dev Includes a public faucet (1,000 tokens per call, 1-hour cooldown) and owner-only
 *      minting. Used exclusively on testnet deployments. Production deployments use the
 *      real USDC contract on the target chain.
 * @author Lindblad Protocol
 * @custom:website https://lindblad.io
 * @custom:repository https://github.com/lindblad-protocol/contracts
 */
contract MockUSDC is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;

    /// @notice Amount minted per faucet call (1,000 USDC).
    uint256 public constant FAUCET_AMOUNT = 1000 * 10**DECIMALS;

    /// @notice Cooldown between faucet claims per address.
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    mapping(address => uint256) public lastFaucetClaim;

    event FaucetClaimed(address indexed user, uint256 amount);

    constructor() ERC20("Mock USDC", "USDC") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000 * 10**DECIMALS);
    }

    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @notice Public faucet — anyone can claim FAUCET_AMOUNT once per FAUCET_COOLDOWN.
     */
    function faucet() external {
        require(
            block.timestamp >= lastFaucetClaim[msg.sender] + FAUCET_COOLDOWN,
            "Faucet on cooldown (1 hour)"
        );
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Owner-only mint, used for funding testnet demo scenarios.
    function mintTo(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
