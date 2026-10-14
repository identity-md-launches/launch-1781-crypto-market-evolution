// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CMEToken} from "../src/CMEToken.sol";

/// @dev Test-only handler. All recipients belong to a closed set so every unit can be accounted for.
contract CMETokenHandler is Test {
    CMEToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = makeAddr("invariant holder 0");
        actors[1] = makeAddr("invariant holder 1");
        actors[2] = makeAddr("invariant holder 2");
        actors[3] = makeAddr("invariant holder 3");
        token = new CMEToken();
        uint256 supply = token.totalSupply();
        assertTrue(token.transfer(actors[0], supply));
        expectedBalance[actors[0]] = supply;
    }

    function move(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % 4];
        address to = actors[toIndex % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount) external {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 fromIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % 4];
        address spender = actors[spenderIndex % 4];
        address to = actors[toIndex % 4];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, 0, balance < allowed ? balance : allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function rejectOverdraw(uint256 fromIndex, uint256 toIndex, uint256 amount) external {
        address from = actors[fromIndex % 4];
        address to = actors[toIndex % 4];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function revoke(uint256 ownerIndex, uint256 spenderIndex) external {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }
}

contract CMETokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CMETokenHandler internal handler;
    CMEToken internal token;

    function setUp() public {
        handler = new CMETokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = CMETokenHandler.move.selector;
        selectors[1] = CMETokenHandler.approve.selector;
        selectors[2] = CMETokenHandler.spend.selector;
        selectors[3] = CMETokenHandler.rejectOverdraw.selector;
        selectors[4] = CMETokenHandler.revoke.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_totalSupplyAndSumOfBalancesRemainFixed() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesMatchIndependentAccounting() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
        }
    }

    function invariant_allowancesMatchApprovalsRevocationsAndSpending() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
