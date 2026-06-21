// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title M2MEscrow
 * @notice Autonomous Machine-to-Machine commerce escrow with hardware-attested verification.
 * @dev Each party is a Lindblad-attested hardware node identified by its PUF-derived
 *      Ethereum address. The address is derived from the node's ECDSA public key, itself
 *      derived in real time from the SRAM PUF via BCH(255,139,t=15) fuzzy extractor.
 *      Registry of authorized nodes is currently managed by the Lindblad Oracle.
 *      Future iterations will use on-chain PUF signature verification for permissionless
 *      registration.
 * @author Lindblad Protocol
 * @custom:website https://lindblad.io
 * @custom:repository https://github.com/lindblad-protocol/contracts
 */
contract M2MEscrow is ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // ============ STATE VARIABLES ============

    /// @notice ERC-20 token used for all escrow payments (e.g., USDC).
    IERC20 public immutable paymentToken;

    /// @notice Address authorized to register Lindblad-attested nodes.
    address public lindbladOracle;

    /**
     * @notice Lifecycle states for an M2M service contract.
     * @dev Transitions: Requested → Accepted → InProgress → Delivered → Settled
     *      Or at any point before delivery: → Cancelled
     */
    enum ServiceState {
        Requested,
        Accepted,
        InProgress,
        Delivered,
        Settled,
        Cancelled
    }

    /**
     * @notice Full state of an M2M service contract.
     * @param requesterNode      The Lindblad node requesting the service (pays in advance).
     * @param providerNode       The Lindblad node providing the service.
     * @param maxAmount          Maximum payment locked in escrow.
     * @param deliveredAmount    Cumulative units delivered so far.
     * @param serviceUnit        Total units requested.
     * @param pricePerUnit       Price per unit in the payment token's smallest denomination.
     * @param createdAt          Block timestamp when the contract was created.
     * @param deadlineAt         Block timestamp after which settlement can be forced.
     * @param state              Current lifecycle state.
     * @param serviceType        Free-form string identifying the service (e.g., "EV_CHARGE").
     * @param lastAttestationHash Hash of the latest off-chain delivery proof.
     */
    struct ServiceContract {
        address requesterNode;
        address providerNode;
        uint256 maxAmount;
        uint256 deliveredAmount;
        uint256 serviceUnit;
        uint256 pricePerUnit;
        uint256 createdAt;
        uint256 deadlineAt;
        ServiceState state;
        string serviceType;
        bytes32 lastAttestationHash;
    }

    mapping(uint256 => ServiceContract) public contracts;
    uint256 public contractCounter;

    /// @notice Registry of Lindblad-attested hardware nodes authorized to participate.
    mapping(address => bool) public registeredNodes;

    // ============ EVENTS ============

    event ServiceRequested(
        uint256 indexed contractId,
        address indexed requester,
        address indexed provider,
        string serviceType,
        uint256 maxAmount
    );

    event ServiceAccepted(uint256 indexed contractId, uint256 timestamp);

    event ServiceAttested(
        uint256 indexed contractId,
        uint256 deliveredAmount,
        bytes32 attestationHash,
        uint256 timestamp
    );

    event ServiceSettled(
        uint256 indexed contractId,
        uint256 paymentAmount,
        uint256 refundAmount,
        uint256 timestamp
    );

    event NodeRegistered(address indexed node);

    // ============ MODIFIERS ============

    modifier onlyLindbladOracle() {
        require(msg.sender == lindbladOracle, "Only Lindblad oracle");
        _;
    }

    modifier onlyRegisteredNode() {
        require(registeredNodes[msg.sender], "Node not registered");
        _;
    }

    // ============ CONSTRUCTOR ============

    /**
     * @param _paymentToken    Address of the ERC-20 token used for payment.
     * @param _lindbladOracle  Address authorized to register nodes.
     */
    constructor(address _paymentToken, address _lindbladOracle) {
        require(_paymentToken != address(0), "Invalid payment token");
        require(_lindbladOracle != address(0), "Invalid oracle");
        paymentToken = IERC20(_paymentToken);
        lindbladOracle = _lindbladOracle;
    }

    // ============ NODE REGISTRY ============

    /**
     * @notice Registers a single Lindblad-attested hardware node.
     * @dev Only callable by the Lindblad Oracle. The address parameter is the Ethereum
     *      address derived from the node's PUF-based ECDSA public key.
     * @param node Ethereum address of the node to register.
     */
    function registerNode(address node) external onlyLindbladOracle {
        require(node != address(0), "Invalid node");
        registeredNodes[node] = true;
        emit NodeRegistered(node);
    }

    /// @notice Batch version of registerNode for gas efficiency.
    function registerNodeBatch(address[] calldata nodes) external onlyLindbladOracle {
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i] != address(0)) {
                registeredNodes[nodes[i]] = true;
                emit NodeRegistered(nodes[i]);
            }
        }
    }

    // ============ M2M COMMERCE FLOW ============

    /**
     * @notice Requester locks payment in escrow and proposes a service contract.
     * @dev The caller must have approved this contract for at least `maxAmount` of the
     *      payment token. State: → Requested.
     * @param provider      Address of the provider node (must be registered).
     * @param serviceUnit   Total units of service requested.
     * @param pricePerUnit  Price per unit in payment token's smallest denomination.
     * @param maxAmount     Maximum payment locked in escrow.
     * @param deadline      Unix timestamp after which settlement can be forced.
     * @param serviceType   Free-form string identifying the service.
     * @return contractId   Unique identifier of the newly created contract.
     */
    function requestService(
        address provider,
        uint256 serviceUnit,
        uint256 pricePerUnit,
        uint256 maxAmount,
        uint256 deadline,
        string calldata serviceType
    ) external onlyRegisteredNode nonReentrant returns (uint256) {
        require(registeredNodes[provider], "Provider not registered");
        require(provider != msg.sender, "Cannot self-request");
        require(maxAmount > 0, "Invalid amount");
        require(serviceUnit > 0, "Invalid service unit");
        require(deadline > block.timestamp, "Invalid deadline");

        require(
            paymentToken.transferFrom(msg.sender, address(this), maxAmount),
            "Payment transfer failed"
        );

        uint256 contractId = contractCounter++;

        contracts[contractId] = ServiceContract({
            requesterNode: msg.sender,
            providerNode: provider,
            maxAmount: maxAmount,
            deliveredAmount: 0,
            serviceUnit: serviceUnit,
            pricePerUnit: pricePerUnit,
            createdAt: block.timestamp,
            deadlineAt: deadline,
            state: ServiceState.Requested,
            serviceType: serviceType,
            lastAttestationHash: bytes32(0)
        });

        emit ServiceRequested(contractId, msg.sender, provider, serviceType, maxAmount);

        return contractId;
    }

    /**
     * @notice Provider accepts the service contract.
     * @dev State: Requested → Accepted.
     */
    function acceptService(uint256 contractId) external onlyRegisteredNode {
        ServiceContract storage sc = contracts[contractId];
        require(sc.providerNode == msg.sender, "Not the provider");
        require(sc.state == ServiceState.Requested, "Invalid state");
        require(block.timestamp < sc.deadlineAt, "Past deadline");

        sc.state = ServiceState.Accepted;
        emit ServiceAccepted(contractId, block.timestamp);
    }

    /**
     * @notice Provider attests cumulative delivery progress.
     * @dev State: Accepted/InProgress → InProgress. Auto-settles when fully delivered.
     * @param contractId          Contract identifier.
     * @param newDeliveredAmount  Cumulative units delivered (must be monotonically increasing).
     * @param attestationHash     Hash of the off-chain delivery proof.
     */
    function attestDelivery(
        uint256 contractId,
        uint256 newDeliveredAmount,
        bytes32 attestationHash
    ) external onlyRegisteredNode {
        ServiceContract storage sc = contracts[contractId];
        require(sc.providerNode == msg.sender, "Not the provider");
        require(
            sc.state == ServiceState.Accepted || sc.state == ServiceState.InProgress,
            "Invalid state"
        );
        require(newDeliveredAmount >= sc.deliveredAmount, "Cannot decrease delivered");
        require(newDeliveredAmount <= sc.serviceUnit, "Exceeds requested units");
        require(block.timestamp < sc.deadlineAt, "Past deadline");

        sc.deliveredAmount = newDeliveredAmount;
        sc.lastAttestationHash = attestationHash;
        sc.state = ServiceState.InProgress;

        emit ServiceAttested(contractId, newDeliveredAmount, attestationHash, block.timestamp);

        if (newDeliveredAmount == sc.serviceUnit) {
            sc.state = ServiceState.Delivered;
            _settlePayment(contractId);
        }
    }

    /**
     * @notice Manual settlement of a contract.
     * @dev Callable by either party. Allowed when fully delivered, or when past deadline
     *      with partial delivery. Pays provider proportionally and refunds remainder
     *      to requester.
     */
    function settlePayment(uint256 contractId) external nonReentrant {
        ServiceContract storage sc = contracts[contractId];
        require(
            msg.sender == sc.requesterNode || msg.sender == sc.providerNode,
            "Unauthorized"
        );
        require(
            sc.state == ServiceState.Delivered ||
            (sc.state == ServiceState.InProgress && block.timestamp >= sc.deadlineAt),
            "Cannot settle yet"
        );

        _settlePayment(contractId);
    }

    function _settlePayment(uint256 contractId) internal {
        ServiceContract storage sc = contracts[contractId];
        require(sc.state != ServiceState.Settled, "Already settled");

        uint256 paymentAmount = sc.deliveredAmount * sc.pricePerUnit;
        if (paymentAmount > sc.maxAmount) {
            paymentAmount = sc.maxAmount;
        }

        uint256 refundAmount = sc.maxAmount - paymentAmount;

        sc.state = ServiceState.Settled;

        if (paymentAmount > 0) {
            require(
                paymentToken.transfer(sc.providerNode, paymentAmount),
                "Provider payment failed"
            );
        }

        if (refundAmount > 0) {
            require(
                paymentToken.transfer(sc.requesterNode, refundAmount),
                "Requester refund failed"
            );
        }

        emit ServiceSettled(contractId, paymentAmount, refundAmount, block.timestamp);
    }

    // ============ VIEW FUNCTIONS ============

    function getContract(uint256 contractId) external view returns (ServiceContract memory) {
        return contracts[contractId];
    }

    function getContractState(uint256 contractId) external view returns (ServiceState) {
        return contracts[contractId].state;
    }

    function isNodeRegistered(address node) external view returns (bool) {
        return registeredNodes[node];
    }
}
