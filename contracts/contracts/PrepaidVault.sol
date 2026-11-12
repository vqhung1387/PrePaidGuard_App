// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";

contract PrepaidVault is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Status { None, Active, Completed, Refunded }

    struct Plan {
        bytes32 clientReference;
        address merchant;
        address token;
        uint256 pricePerPeriod;
        uint32 totalPeriods;
        uint64 periodDuration;
        uint64 gracePeriod;
    }

    struct Subscription {
        uint256 planId;
        address subscriber;
        uint256 initialPrincipal;
        uint256 remainingPrincipal;
        uint32 completedPeriods;
        uint256 nonce;
        uint64 startedAt;
        uint64 nextReleaseAt;
        Status status;
    }

    struct CheckIn {
        uint256 subscriptionId;
        address merchant;
        uint256 periodIndex;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 public constant CHECK_IN_TYPEHASH = keccak256(
        "CheckIn(uint256 subscriptionId,address merchant,uint256 periodIndex,uint256 nonce,uint256 deadline)"
    );
    uint256 public constant CHECK_IN_TTL = 900;
    IERC20 public immutable paymentToken;
    address public immutable treasury;
    IYieldAdapter public immutable adapter;
    uint256 public planCount;
    uint256 public subscriptionCount;
    uint256 public totalPrincipal;
    mapping(uint256 => Plan) private plans;
    mapping(uint256 => Subscription) private subscriptions;
    mapping(address => mapping(bytes32 => bool)) public usedReference;

    error InvalidConfiguration();
    error InvalidPlan();
    error InvalidSubscription();
    error InvalidTerms();
    error DuplicateReference();
    error Unauthorized();
    error TerminalSubscription();
    error CheckInWindowClosed();
    error RefundNotAvailable();
    error InvalidDeadline();
    error InvalidCheckIn();
    error InvalidSignature();
    error UnsupportedToken();
    error AdapterShortfall();

    event PlanCreated(
        uint256 indexed planId, address indexed merchant, bytes32 indexed clientReference,
        address token, uint256 pricePerPeriod, uint32 totalPeriods, uint64 periodDuration, uint64 gracePeriod
    );
    event Subscribed(
        uint256 indexed subscriptionId, uint256 indexed planId, address subscriber,
        uint256 principal, uint64 startedAt, uint64 nextReleaseAt
    );
    event PeriodReleased(
        uint256 indexed subscriptionId, uint256 planId, uint256 periodIndex, uint256 principal,
        uint256 merchantYield, uint256 subscriberYield, uint256 platformYield, uint256 nonceAfter,
        uint64 nextReleaseAt, bool completed
    );
    event Refunded(
        uint256 indexed subscriptionId, uint256 planId, uint256 principal,
        uint256 merchantYield, uint256 subscriberYield, uint256 platformYield, uint256 nonceAfter
    );

    constructor(IERC20 token_, address treasury_, IYieldAdapter adapter_) EIP712("PrepaidGuard", "1") {
        if (
            address(token_).code.length == 0 || treasury_ == address(0)
                || treasury_ == address(this) || IERC20Metadata(address(token_)).decimals() != 6
        ) revert InvalidConfiguration();
        if (address(adapter_) != address(0)) {
            if (
                address(adapter_).code.length == 0 || address(adapter_.token()) != address(token_)
                    || adapter_.vault() != address(0)
            ) revert InvalidConfiguration();
        }
        paymentToken = token_;
        treasury = treasury_;
        adapter = adapter_;
    }

    function getPlan(uint256 planId) external view returns (Plan memory) {
        if (plans[planId].merchant == address(0)) revert InvalidPlan();
        return plans[planId];
    }

    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {
        if (subscriptions[subscriptionId].subscriber == address(0)) revert InvalidSubscription();
        return subscriptions[subscriptionId];
    }

    function createPlan(
        bytes32 clientReference, address token, uint256 pricePerPeriod,
        uint32 totalPeriods, uint64 periodDuration, uint64 gracePeriod
    ) external returns (uint256 planId) {
        if (
            token != address(paymentToken) || clientReference == bytes32(0) || pricePerPeriod == 0
                || totalPeriods == 0 || totalPeriods > 120
                || pricePerPeriod > type(uint256).max / totalPeriods
                || periodDuration == 0 || gracePeriod == 0
                || uint256(periodDuration) + gracePeriod >= 2 ** 63
        ) revert InvalidTerms();
        if (usedReference[msg.sender][clientReference]) revert DuplicateReference();
        usedReference[msg.sender][clientReference] = true;
        planId = ++planCount;
        plans[planId] = Plan(
            clientReference, msg.sender, token, pricePerPeriod, totalPeriods, periodDuration, gracePeriod
        );
        emit PlanCreated(
            planId, msg.sender, clientReference, token, pricePerPeriod, totalPeriods, periodDuration, gracePeriod
        );
    }

    function subscribe(uint256 planId) external nonReentrant returns (uint256 subscriptionId) {
        Plan storage plan = plans[planId];
        if (plan.merchant == address(0)) revert InvalidPlan();
        uint256 principal = plan.pricePerPeriod * plan.totalPeriods;
        uint64 startedAt = _timestamp(block.timestamp);
        uint64 nextReleaseAt = _timestamp(block.timestamp + plan.periodDuration);
        subscriptionId = ++subscriptionCount;
        subscriptions[subscriptionId] = Subscription(
            planId, msg.sender, principal, principal, 0, 0, startedAt, nextReleaseAt, Status.Active
        );
        totalPrincipal += principal;
        uint256 beforeBalance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), principal);
        if (paymentToken.balanceOf(address(this)) - beforeBalance != principal) revert UnsupportedToken();
        if (address(adapter) != address(0)) {
            if (adapter.vault() != address(this)) revert InvalidConfiguration();
            paymentToken.forceApprove(address(adapter), principal);
            adapter.deposit(subscriptionId, principal);
            paymentToken.forceApprove(address(adapter), 0);
            if (paymentToken.balanceOf(address(this)) != beforeBalance) revert AdapterShortfall();
        }
        emit Subscribed(subscriptionId, planId, msg.sender, principal, startedAt, nextReleaseAt);
    }

    function checkInWithSignature(CheckIn calldata checkIn, bytes calldata signature) external nonReentrant {
        Subscription storage sub = _active(checkIn.subscriptionId);
        Plan storage plan = plans[sub.planId];
        if (msg.sender != plan.merchant || checkIn.merchant != plan.merchant) revert Unauthorized();
        if (
            block.timestamp < sub.nextReleaseAt || block.timestamp >= uint256(sub.nextReleaseAt) + plan.gracePeriod
        ) revert CheckInWindowClosed();
        if (checkIn.deadline < block.timestamp || checkIn.deadline > block.timestamp + CHECK_IN_TTL) {
            revert InvalidDeadline();
        }
        if (checkIn.nonce != sub.nonce || checkIn.periodIndex != uint256(sub.completedPeriods) + 1) {
            revert InvalidCheckIn();
        }
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            CHECK_IN_TYPEHASH, checkIn.subscriptionId, checkIn.merchant,
            checkIn.periodIndex, checkIn.nonce, checkIn.deadline
        )));
        if (ECDSA.recover(digest, signature) != sub.subscriber) revert InvalidSignature();

        sub.completedPeriods++;
        sub.nonce++;
        sub.remainingPrincipal -= plan.pricePerPeriod;
        totalPrincipal -= plan.pricePerPeriod;
        sub.nextReleaseAt = _timestamp(block.timestamp + plan.periodDuration);
        bool completed = sub.completedPeriods == plan.totalPeriods;
        if (completed) sub.status = Status.Completed;
        (uint256 merchantYield, uint256 subscriberYield, uint256 platformYield) =
            _pay(checkIn.subscriptionId, plan.pricePerPeriod, plan.merchant, sub.subscriber, plan.merchant);
        emit PeriodReleased(
            checkIn.subscriptionId, sub.planId, sub.completedPeriods, plan.pricePerPeriod,
            merchantYield, subscriberYield, platformYield, sub.nonce, sub.nextReleaseAt, completed
        );
    }

    function refund(uint256 subscriptionId) external nonReentrant {
        Subscription storage sub = _active(subscriptionId);
        if (msg.sender != sub.subscriber) revert Unauthorized();
        Plan storage plan = plans[sub.planId];
        if (block.timestamp < uint256(sub.nextReleaseAt) + plan.gracePeriod) revert RefundNotAvailable();
        uint256 principal = sub.remainingPrincipal;
        sub.remainingPrincipal = 0;
        sub.status = Status.Refunded;
        sub.nonce++;
        totalPrincipal -= principal;
        (uint256 merchantYield, uint256 subscriberYield, uint256 platformYield) =
            _pay(subscriptionId, principal, sub.subscriber, sub.subscriber, plan.merchant);
        emit Refunded(subscriptionId, sub.planId, principal, merchantYield, subscriberYield, platformYield, sub.nonce);
    }

    function estimateYield(uint256 subscriptionId) external view returns (uint256) {
        if (subscriptions[subscriptionId].subscriber == address(0)) revert InvalidSubscription();
        return address(adapter) == address(0) ? 0 : adapter.estimateYield(subscriptionId);
    }

    function _active(uint256 subscriptionId) private view returns (Subscription storage sub) {
        sub = subscriptions[subscriptionId];
        if (sub.subscriber == address(0)) revert InvalidSubscription();
        if (sub.status != Status.Active) revert TerminalSubscription();
    }

    function _timestamp(uint256 value) private pure returns (uint64) {
        if (value > type(uint64).max) revert InvalidTerms();
        return uint64(value);
    }

    function _pay(uint256 subscriptionId, uint256 principal, address recipient, address subscriber, address merchant)
        private returns (uint256 merchantYield, uint256 subscriberYield, uint256 platformYield)
    {
        uint256 realizedYield;
        if (address(adapter) != address(0)) {
            uint256 beforeBalance = paymentToken.balanceOf(address(this));
            realizedYield = adapter.withdraw(subscriptionId, principal);
            if (paymentToken.balanceOf(address(this)) - beforeBalance != principal + realizedYield) revert AdapterShortfall();
        }
        merchantYield = Math.mulDiv(realizedYield, 70, 100);
        subscriberYield = Math.mulDiv(realizedYield, 20, 100);
        platformYield = realizedYield - merchantYield - subscriberYield;
        paymentToken.safeTransfer(recipient, principal);
        if (merchantYield != 0) paymentToken.safeTransfer(merchant, merchantYield);
        if (subscriberYield != 0) paymentToken.safeTransfer(subscriber, subscriberYield);
        if (platformYield != 0) paymentToken.safeTransfer(treasury, platformYield);
    }
}
