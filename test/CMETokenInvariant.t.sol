// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CMEToken} from "../src/CMEToken.sol";

/// @dev Test-only handler. All recipients belong to a closed set so every unit can be accounted for.
contract CMETokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
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
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        for (uint256 i; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / actors.length));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            // Start with useful finite and unlimited approvals so delegated calls
            // exercise nonzero transfers before the first random approval.
            _approve(actors[i], actors[(i + 1) % actors.length], SUPPLY / actors.length);
            _approve(actors[i], actors[(i + 2) % actors.length], type(uint256).max);
        }
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

    function approve(uint256 ownerIndex, uint256 spenderIndex, uint256 amount, uint8 mode) external {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        // Preserve unrestricted uint256 approvals as well as frequently exercising
        // allowances small enough to exhaust and the unlimited sentinel.
        if (mode % 3 == 1) amount = bound(amount, 0, SUPPLY);
        else if (mode % 3 == 2) amount = type(uint256).max;
        _approve(owner, spender, amount);
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
        _approve(owner, spender, 0);
    }

    function rejectOverAllowance(
        uint256 ownerIndex,
        uint256 spenderIndex,
        uint256 toIndex,
        uint256 allowed,
        uint256 amount
    ) external {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        address to = actors[toIndex % 4];
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, allowed + 1, type(uint256).max);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        assertEq(token.allowance(owner, spender), allowed);
    }

    function rejectDelegatedOverdraw(uint256 ownerIndex, uint256 spenderIndex, uint256 toIndex, uint256 amount)
        external
    {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        address to = actors[toIndex % 4];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, balance + 1, type(uint256).max);
        // Sufficient approval reaches the balance failure after allowance spending.
        // The failed call must roll that spending back, including for self-transfers.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        assertEq(token.allowance(owner, spender), amount);
    }

    function rejectZeroRecipient(uint256 ownerIndex, uint256 spenderIndex, uint256 amount, bool delegated) external {
        address owner = actors[ownerIndex % 4];
        address spender = actors[spenderIndex % 4];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) limit = expectedAllowance[owner][spender];
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerIndex, uint256 amount) external {
        address owner = actors[ownerIndex % 4];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract CMETokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CMETokenHandler internal handler;
    CMEToken internal token;

    function setUp() public {
        handler = new CMETokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = CMETokenHandler.move.selector;
        selectors[1] = CMETokenHandler.approve.selector;
        selectors[2] = CMETokenHandler.spend.selector;
        selectors[3] = CMETokenHandler.rejectOverdraw.selector;
        selectors[4] = CMETokenHandler.revoke.selector;
        selectors[5] = CMETokenHandler.rejectOverAllowance.selector;
        selectors[6] = CMETokenHandler.rejectDelegatedOverdraw.selector;
        selectors[7] = CMETokenHandler.rejectZeroRecipient.selector;
        selectors[8] = CMETokenHandler.rejectZeroSpender.selector;
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
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_balancesMatchIndependentAccounting() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
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

    function invariant_metadataRemainsUnchanged() public view {
        assertEq(token.name(), "Crypto Market Evolution");
        assertEq(token.symbol(), "CME");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }
}
