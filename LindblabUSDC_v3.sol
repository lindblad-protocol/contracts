// SPDX-License-Identifier: MIT
// ─────────────────────────────────────────────
// Lindblad Protocol
// Deployed on Arbitrum One (mainnet)
// Address: 0x1AfC80b30cBBE50E8aBb4585f53ff530c305d416
// Network: Arbitrum One — Chain ID 42161
// Explorer: https://arbiscan.io/address/0x1AfC80b30cBBE50E8aBb4585f53ff530c305d416
// ─────────────────────────────────────────────
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function burn(uint256 amount) external;
}

/**
 * @title LindblabUSDC v3
 * @notice Hardware-Enforced Bridge with PYCO fee mechanism
 * @dev Withdraw requires 0.1% fee in PYCO (50% burned, 50% to treasury)
 */
contract LindblabUSDC {
    address public owner;
    address public usdc;
    address public pyco;
    address public treasury;
    bool public paused = false;
    uint256 public signatureExpiry = 300; // 5 minutes
    uint256 public feeRateBps = 10; // 0.1% = 10 basis points (10/10000)

    // Hardware nodes (SRAM PUF + Chua)
    struct NodeKey { uint256 qx; uint256 qy; bool active; }
    mapping(bytes32 => NodeKey) public nodes;

    // Software devices (WebCrypto P-256)
    struct DeviceKey { uint256 qx; uint256 qy; bool active; }
    mapping(bytes32 => DeviceKey) public devices;

    mapping(bytes32 => bool) public usedSignatures;
    mapping(string => uint256) public lindBalance;
    uint256 public totalDeposited;

    event Deposited(address indexed user, string lindAddr, uint256 amount);
    event Withdrawn(address indexed to, string lindAddr, uint256 amount, uint256 pycoFee);
    event NodeRegistered(string nodeId);
    event DeviceRegistered(string lindAddr);
    event FeeRateUpdated(uint256 newRate);

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier notPaused() { require(!paused, "Paused"); _; }

    struct WithdrawParams {
        string lindAddr;
        address toWallet;
        uint256 amount;
        string signerId;
        string challenge;
        uint256 ts;
        string chuaNonce;
        bytes32 r;
        bytes32 s;
    }

    constructor(address _usdc, address _pyco, address _treasury) {
        owner = msg.sender;
        usdc = _usdc;
        pyco = _pyco;
        treasury = _treasury;
    }

    function registerNode(string calldata nodeId, bytes calldata pubKey) external onlyOwner {
        require(pubKey.length == 65 && pubKey[0] == 0x04, "Invalid pubkey");
        bytes32 k = keccak256(bytes(nodeId));
        nodes[k] = NodeKey(uint256(bytes32(pubKey[1:33])), uint256(bytes32(pubKey[33:65])), true);
        emit NodeRegistered(nodeId);
    }

    function registerDevice(string calldata lindAddr, bytes calldata pubKey) external {
        require(pubKey.length == 65 && pubKey[0] == 0x04, "Invalid pubkey");
        bytes32 k = keccak256(bytes(lindAddr));
        devices[k] = DeviceKey(uint256(bytes32(pubKey[1:33])), uint256(bytes32(pubKey[33:65])), true);
        emit DeviceRegistered(lindAddr);
    }

    function deposit(string calldata lindAddr, uint256 amount) external notPaused {
        require(amount > 0, "Zero amount");
        require(IERC20(usdc).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        lindBalance[lindAddr] += amount;
        totalDeposited += amount;
        emit Deposited(msg.sender, lindAddr, amount);
    }

    function withdraw(WithdrawParams calldata p) external notPaused {
        require(block.timestamp <= p.ts + signatureExpiry, "Expired");

        bytes32 msgHash = sha256(abi.encodePacked(p.challenge, p.signerId, _uint2str(p.ts), p.chuaNonce));
        bytes32 sigId = keccak256(abi.encodePacked(p.r, p.s));
        require(!usedSignatures[sigId], "Replay");

        // Verify signature
        bool verified = false;
        if (keccak256(bytes(p.signerId)) == keccak256(bytes("DEVICE"))) {
            DeviceKey memory dk = devices[keccak256(bytes(p.lindAddr))];
            require(dk.active, "Device not registered");
            verified = _verifyP256(msgHash, uint256(p.r), uint256(p.s), dk.qx, dk.qy);
        } else {
            NodeKey memory nk = nodes[keccak256(bytes(p.signerId))];
            require(nk.active, "Node inactive");
            verified = _verifyP256(msgHash, uint256(p.r), uint256(p.s), nk.qx, nk.qy);
        }
        require(verified, "Bad signature");

        usedSignatures[sigId] = true;
        require(lindBalance[p.lindAddr] >= p.amount, "Insufficient");

        // Calculate PYCO fee
        uint256 pycoFee = 0;
        if (pyco != address(0) && feeRateBps > 0) {
            // fee = amount * feeRateBps / 10000 (both in 6 decimals)
            pycoFee = (p.amount * feeRateBps) / 10000;
            if (pycoFee > 0) {
                // Transfer PYCO fee from user
                require(IERC20(pyco).transferFrom(msg.sender, address(this), pycoFee), "PYCO fee failed");
                uint256 burnAmount = pycoFee / 2;
                uint256 treasuryAmount = pycoFee - burnAmount;
                // Burn 50%
                if (burnAmount > 0) IERC20(pyco).burn(burnAmount);
                // Send 50% to treasury (node operators)
                if (treasuryAmount > 0) IERC20(pyco).transfer(treasury, treasuryAmount);
            }
        }

        lindBalance[p.lindAddr] -= p.amount;
        totalDeposited -= p.amount;
        require(IERC20(usdc).transfer(p.toWallet, p.amount), "Transfer failed");
        emit Withdrawn(p.toWallet, p.lindAddr, p.amount, pycoFee);
    }

    // Calculate PYCO fee for a given amount
    function calcFee(uint256 amount) external view returns (uint256) {
        return (amount * feeRateBps) / 10000;
    }

    // ── P-256 ──
    uint256 constant P256_P  = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
    uint256 constant P256_N  = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;
    uint256 constant P256_A  = 0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc;
    uint256 constant P256_GX = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    uint256 constant P256_GY = 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5;

    function _verifyP256(bytes32 hash, uint256 r, uint256 s, uint256 qx, uint256 qy) internal view returns (bool) {
        (bool ok, bytes memory res) = address(0x100).staticcall(abi.encode(hash, r, s, qx, qy));
        if (ok && res.length >= 32 && abi.decode(res, (uint256)) == 1) return true;
        return _p256Verify(uint256(hash), r, s, qx, qy);
    }

    function _p256Verify(uint256 e, uint256 r, uint256 s, uint256 qx, uint256 qy) internal pure returns (bool) {
        unchecked {
            if (r == 0 || r >= P256_N || s == 0 || s >= P256_N) return false;
            uint256 w = _inv(s, P256_N);
            uint256[2] memory res = _ecAdd(_ecMul(P256_GX, P256_GY, mulmod(e, w, P256_N)), _ecMul(qx, qy, mulmod(r, w, P256_N)));
            return (res[0] % P256_N) == r;
        }
    }

    function _inv(uint256 a, uint256 m) internal pure returns (uint256 res) {
        unchecked {
            int256 t = 0; int256 nt = 1; uint256 r = m; uint256 nr = a % m;
            while (nr != 0) { uint256 q = r / nr; (t, nt) = (nt, t - int256(q) * nt); (r, nr) = (nr, r - q * nr); }
            if (t < 0) t += int256(m);
            res = uint256(t);
        }
    }

    function _ecAdd(uint256[2] memory P, uint256[2] memory Q) internal pure returns (uint256[2] memory R) {
        unchecked {
            if (P[0] == 0 && P[1] == 0) return Q;
            if (Q[0] == 0 && Q[1] == 0) return P;
            if (P[0] == Q[0]) { if (P[1] == Q[1]) return _ecDbl(P); return [uint256(0), uint256(0)]; }
            uint256 lam = mulmod(addmod(Q[1], P256_P - P[1], P256_P), _inv(addmod(Q[0], P256_P - P[0], P256_P), P256_P), P256_P);
            R[0] = addmod(mulmod(lam, lam, P256_P), P256_P - addmod(P[0], Q[0], P256_P), P256_P);
            R[1] = addmod(mulmod(lam, addmod(P[0], P256_P - R[0], P256_P), P256_P), P256_P - P[1], P256_P);
        }
    }

    function _ecDbl(uint256[2] memory P) internal pure returns (uint256[2] memory R) {
        unchecked {
            uint256 lam = mulmod(addmod(mulmod(3, mulmod(P[0], P[0], P256_P), P256_P), P256_A, P256_P), _inv(mulmod(2, P[1], P256_P), P256_P), P256_P);
            R[0] = addmod(mulmod(lam, lam, P256_P), P256_P - mulmod(2, P[0], P256_P), P256_P);
            R[1] = addmod(mulmod(lam, addmod(P[0], P256_P - R[0], P256_P), P256_P), P256_P - P[1], P256_P);
        }
    }

    function _ecMul(uint256 px, uint256 py, uint256 k) internal pure returns (uint256[2] memory R) {
        unchecked {
            uint256[2] memory Q = [px, py];
            while (k > 0) { if (k & 1 == 1) R = _ecAdd(R, Q); Q = _ecDbl(Q); k >>= 1; }
        }
    }

    function _uint2str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0"; uint256 t = v; uint256 d;
        while (t != 0) { d++; t /= 10; }
        bytes memory b = new bytes(d);
        while (v != 0) { d--; b[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }

    function setPaused(bool _p) external onlyOwner { paused = _p; }
    function setExpiry(uint256 _s) external onlyOwner { signatureExpiry = _s; }
    function setFeeRate(uint256 _bps) external onlyOwner { require(_bps <= 100, "Max 1%"); feeRateBps = _bps; emit FeeRateUpdated(_bps); }
    function setTreasury(address _t) external onlyOwner { treasury = _t; }
    function setPyco(address _p) external onlyOwner { pyco = _p; }
    function deactivateNode(string calldata nodeId) external onlyOwner { nodes[keccak256(bytes(nodeId))].active = false; }
    function deactivateDevice(string calldata lindAddr) external onlyOwner { devices[keccak256(bytes(lindAddr))].active = false; }
    function emergencyWithdraw() external onlyOwner {
        uint256 bal = IERC20(usdc).balanceOf(address(this));
        IERC20(usdc).transfer(owner, bal);
    }
}
