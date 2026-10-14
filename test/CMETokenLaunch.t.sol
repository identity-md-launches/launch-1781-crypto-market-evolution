// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CMEToken} from "../src/CMEToken.sol";

/// @dev Test-only deployment and transfer harness, not an application contract.
contract CMEFactoryHarness {
    function deploy(bytes32 salt) external returns (CMEToken) {
        return new CMEToken{salt: salt}();
    }

    function move(CMEToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// @dev If the token tried a receiver callback, this recipient would reject it.
contract RejectingReceiver {
    fallback() external {
        revert("no callbacks");
    }
}

contract CMETokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function testFuzz_create2MintsToFactoryWithoutConstructorArguments(bytes32 salt) public {
        CMEFactoryHarness factory = new CMEFactoryHarness();
        bytes32 creationHash = keccak256(type(CMEToken).creationCode);
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, creationHash)))));

        CMEToken token = factory.deploy(salt);
        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.decimals(), 18);
    }

    function test_deploymentMintsToImmediateCaller() public {
        address deployer = makeAddr("direct deployer");
        vm.prank(deployer);
        CMEToken token = new CMEToken();
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Transfer accounting smoke test. This does not instantiate a Uniswap pool.
    function test_launchDistributionClaimsAndPoolTransfersAreExact() public {
        CMEFactoryHarness factory = new CMEFactoryHarness();
        CMEToken token = factory.deploy(keccak256("launch flow test"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_800 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;
        factory.move(token, distributor, swarm);
        factory.move(token, poolManager, pool);
        factory.move(token, remainderRecipient, remainder);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(remainderRecipient), SUPPLY * 200 / 10_000);
        assertEq(token.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);

        uint256 bought = 12_345 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(poolManager), pool - bought);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(claimant) + token.balanceOf(poolManager) + token.balanceOf(remainderRecipient), SUPPLY);
    }

    function test_transfersToContractsDoNotInvokeCallbacks() public {
        CMEToken token = new CMEToken();
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1 ether));
        assertEq(token.balanceOf(address(receiver)), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
