// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CMEToken} from "src/CMEToken.sol";

/// @dev An ordinary intermediary, with neither tokens nor approvals of its own.
contract CMEUnapprovedForwarder {
    function transfer(CMEToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    function transferFrom(CMEToken token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev Complements the original suite with boundary, isolation, and rollback properties.
/// forge-config: default.fuzz.runs = 1024
contract CMETokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CMEToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new CMEToken();
        alice = makeAddr("adversarial alice");
        bob = makeAddr("adversarial bob");
        spender = makeAddr("adversarial spender");
    }

    function test_oneBaseUnitCanBeTransferredAndSpent() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertConservation();
    }

    function test_maximumTransferRevertsWithoutArithmeticPanic() public {
        uint256 maximum = type(uint256).max;
        bytes memory errorData =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum);
        vm.expectRevert(errorData);
        token.transfer(alice, maximum);
        vm.expectRevert(errorData);
        token.transfer(address(this), maximum);

        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(address(this), address(this), maximum);

        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        _assertConservation();
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        uint256 allowed = type(uint256).max - 1;
        assertTrue(token.approve(spender, allowed));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), allowed - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), allowed - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        _assertConservation();
    }

    function test_unlimitedApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 2));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        _assertConservation();
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        bytes memory errorData = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2);
        vm.expectRevert(errorData);
        vm.prank(alice);
        token.transfer(alice, 2);
        vm.expectRevert(errorData);
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 2);
        _assertConservation();
    }

    function test_transferFromByOwnerStillRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), SUPPLY));
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        _assertConservation();
    }

    function test_zeroTransferFromPreservesFiniteAndInfiniteApprovals() public {
        uint256[2] memory approvals = [uint256(7), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            // Approval is valid even though Alice has no balance.
            vm.prank(alice);
            assertTrue(token.approve(spender, approvals[i]));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, alice, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
        }
        _assertConservation();
    }

    function test_zeroRecipientRevertsWithZeroFiniteAndInfiniteAllowances() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            uint256 amount = i == 0 ? 0 : 1;
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), amount);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
        }
        _assertConservation();
    }

    function test_zeroSpenderRejectedForZeroAndMaximumApprovals() public {
        assertTrue(token.approve(spender, 7));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), type(uint256).max);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function test_approvalsDoNotFollowTransferredTokens() public {
        assertTrue(token.approve(spender, SUPPLY));
        assertTrue(token.transfer(alice, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        // The original owner's approval remains usable after that owner is funded again.
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        _assertConservation();
    }

    function test_forwarderCannotSpendUsingOriginApproval() public {
        CMEUnapprovedForwarder forwarder = new CMEUnapprovedForwarder();
        assertTrue(token.approve(alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(forwarder), 0, 1)
        );
        vm.prank(alice, alice);
        forwarder.transferFrom(token, address(this), bob, 1);
        assertEq(token.allowance(address(this), alice), 1);
        assertEq(token.allowance(address(this), address(forwarder)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice, alice);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), alice), 0);
        assertEq(token.balanceOf(bob), 1);
        _assertConservation();
    }

    function test_forwarderCannotTransferOriginBalance() public {
        CMEUnapprovedForwarder forwarder = new CMEUnapprovedForwarder();
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(forwarder), 0, 1)
        );
        vm.prank(alice, alice);
        forwarder.transfer(token, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(forwarder)), 0);
        _assertConservation();
    }

    function testFuzz_failedOverdrawPreservesApprovalForLaterFunding(
        uint256 held,
        uint256 missing,
        bool unlimited,
        bool selfRecipient
    ) public {
        held = bound(held, 0, SUPPLY - 1);
        missing = bound(missing, 1, SUPPLY - held);
        uint256 amount = held + missing;
        uint256 allowed = unlimited ? type(uint256).max : amount;
        address recipient = selfRecipient ? alice : bob;
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, recipient, amount);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);

        assertTrue(token.transfer(alice, missing));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, recipient, amount));
        assertEq(token.allowance(alice, spender), unlimited ? allowed : 0);
        assertEq(token.balanceOf(alice), selfRecipient ? amount : 0);
        assertEq(token.balanceOf(bob), selfRecipient ? 0 : amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        _assertConservation();
    }

    function testFuzz_invalidRecipientPreservesApprovalForValidRetry(uint256 amount, uint256 extra, bool unlimited)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        extra = bound(extra, 0, type(uint256).max - 1 - amount);
        uint256 allowed = unlimited ? type(uint256).max : amount + extra;
        assertTrue(token.approve(spender, allowed));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), unlimited ? allowed : extra);
        _assertConservation();
    }

    function testFuzz_transferRoundTripRestoresBalancesWithoutSpendingApprovals(uint256 amount, uint256 allowed)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(spender, allowed));
        vm.prank(alice);
        assertTrue(token.approve(spender, allowed));
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.allowance(alice, spender), allowed);
        _assertConservation();
    }

    function testFuzz_splitDelegatedSpendingEqualsSingleSpend(uint256 total, uint256 first, bool unlimited) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        uint256 allowed = unlimited ? type(uint256).max : total;
        assertTrue(token.approve(spender, allowed));
        uint256 snapshot = vm.snapshotState();

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, total));
        uint256 ownerBalance = token.balanceOf(address(this));
        uint256 recipientBalance = token.balanceOf(bob);
        uint256 remainingAllowance = token.allowance(address(this), spender);
        _assertConservation();

        assertTrue(vm.revertToStateAndDelete(snapshot));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, total - first));
        assertEq(token.balanceOf(address(this)), ownerBalance);
        assertEq(token.balanceOf(bob), recipientBalance);
        assertEq(token.allowance(address(this), spender), remainingAllowance);
        assertEq(recipientBalance, total);
        assertEq(remainingAllowance, unlimited ? allowed : 0);
        _assertConservation();
    }

    function testFuzz_approvalReplacementAndRepetitionLeaveBalancesUntouched(uint256 first, uint256 last) public {
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(alice, first));
        assertTrue(token.approve(spender, last));
        assertTrue(token.approve(spender, last));
        assertEq(token.allowance(address(this), spender), last);
        assertEq(token.allowance(address(this), alice), first);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        _assertConservation();
    }

    function _assertConservation() internal view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
