// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {PrepaidVault} from "../PrepaidVault.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";
import {MockYieldAdapter} from "../mocks/MockYieldAdapter.sol";
import {IYieldAdapter} from "../interfaces/IYieldAdapter.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8, bytes32, bytes32);
}

contract ConservationTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Fuzz mixed release/refund sequences over three independent positions.
    function testFuzzConservation(uint96 priceSeed, uint8 periodsSeed, uint256 actions, bool yieldEnabled) public {
        MockUSDC token = new MockUSDC(address(this));
        MockYieldAdapter adapter = yieldEnabled ? new MockYieldAdapter(token, address(this)) : MockYieldAdapter(address(0));
        address treasury = address(0xFEE);
        PrepaidVault vault = new PrepaidVault(token, treasury, IYieldAdapter(address(adapter)));
        if (yieldEnabled) adapter.bindVault(address(vault));
        uint256 price = uint256(priceSeed) + 1;
        uint32 periods = uint32(periodsSeed % 6) + 1;
        uint256 principal = price * periods;
        vault.createPlan(bytes32(uint256(1)), address(token), price, periods, 10, 20);
        address[3] memory customers;
        uint256 fundedYield;
        for (uint256 i; i < 3; i++) {
            customers[i] = vm.addr(i + 1);
            token.mint(customers[i], principal);
            vm.prank(customers[i]);
            token.approve(address(vault), principal);
            vm.prank(customers[i]);
            vault.subscribe(1);
            if (yieldEnabled) {
                uint256 amount = (actions >> (i * 8)) % 1000 + 1;
                fundedYield += amount;
                token.mint(address(this), amount);
                token.approve(address(adapter), amount);
                adapter.fundYield(i + 1, amount);
            }
        }
        for (uint256 step; step < 18; step++) {
            uint256 index = uint256(keccak256(abi.encode(actions, step))) % 3;
            PrepaidVault.Subscription memory sub = vault.getSubscription(index + 1);
            if (sub.status != PrepaidVault.Status.Active) continue;
            if ((actions >> step) & 1 == 1 || block.timestamp >= uint256(sub.nextReleaseAt) + 20) {
                if (block.timestamp < uint256(sub.nextReleaseAt) + 20) vm.warp(uint256(sub.nextReleaseAt) + 20);
                vm.prank(customers[index]);
                vault.refund(index + 1);
            } else {
                if (block.timestamp < sub.nextReleaseAt) vm.warp(sub.nextReleaseAt);
                _release(vault, index + 1, sub);
            }
            _conserved(vault, token, adapter, customers, principal * 3 + fundedYield);
        }
    }

    /// @dev Generate representable schedules whose refund endpoint is exactly the shared maximum.
    function testFuzzRefundAtMaximum(uint32 periodSeed, uint32 graceSeed) public {
        MockUSDC token = new MockUSDC(address(this));
        PrepaidVault vault = new PrepaidVault(token, address(0xFEE), IYieldAdapter(address(0)));
        uint64 period = uint64(periodSeed % 365 days) + 1;
        uint64 grace = uint64(graceSeed % 90 days) + 1;
        address customer = vm.addr(1);
        token.mint(customer, 1);
        vm.prank(customer);
        token.approve(address(vault), 1);
        vm.warp(vault.MAX_TIMESTAMP() - period - grace);
        vault.createPlan(bytes32(uint256(1)), address(token), 1, 1, period, grace);
        vm.prank(customer);
        vault.subscribe(1);
        PrepaidVault.Subscription memory sub = vault.getSubscription(1);
        assert(uint256(sub.nextReleaseAt) + grace == vault.MAX_TIMESTAMP());
        assert(sub.remainingPrincipal == 1);
        vm.warp(vault.MAX_TIMESTAMP());
        vm.prank(customer);
        vault.refund(1);
        assert(token.balanceOf(customer) == 1);
        assert(token.balanceOf(address(vault)) == 0);
        assert(vault.totalPrincipal() == 0);
        assert(vault.getSubscription(1).status == PrepaidVault.Status.Refunded);
    }

    function _release(PrepaidVault vault, uint256 id, PrepaidVault.Subscription memory sub) private {
        PrepaidVault.CheckIn memory message = PrepaidVault.CheckIn(
            id, address(this), uint256(sub.completedPeriods) + 1, sub.nonce, block.timestamp + 900
        );
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("PrepaidGuard"), keccak256("1"), block.chainid, address(vault)
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            hex"1901", domain, keccak256(abi.encode(vault.CHECK_IN_TYPEHASH(), message))
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(id, digest);
        vault.checkInWithSignature(message, abi.encodePacked(r, s, v));
    }

    function _conserved(
        PrepaidVault vault, MockUSDC token, MockYieldAdapter adapter, address[3] memory customers, uint256 total
    ) private view {
        uint256 remaining;
        uint256 customerBalances;
        uint256 price = vault.getPlan(1).pricePerPeriod;
        for (uint256 i; i < 3; i++) {
            PrepaidVault.Subscription memory position = vault.getSubscription(i + 1);
            remaining += position.remainingPrincipal;
            customerBalances += token.balanceOf(customers[i]);
            assert(position.remainingPrincipal + price * position.completedPeriods <= position.initialPrincipal);
            if (position.status != PrepaidVault.Status.Active) assert(position.remainingPrincipal == 0);
            if (address(adapter) != address(0)) assert(adapter.principalOf(i + 1) == position.remainingPrincipal);
        }
        assert(vault.totalPrincipal() == remaining);
        uint256 custody = token.balanceOf(address(vault)) + token.balanceOf(address(adapter));
        assert(custody >= remaining);
        assert(custody + customerBalances + token.balanceOf(address(this)) + token.balanceOf(address(0xFEE)) == total);
        if (address(adapter) != address(0)) assert(custody == adapter.totalPrincipal() + adapter.totalYield());
        else assert(custody == remaining);
    }
}
