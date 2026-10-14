# Crypto Market Evolution (CME)

An immutable ERC-20 token that creates its entire supply once, in its constructor.

| Deployment property | Value |
| --- | --- |
| Solidity contract | `CMEToken` |
| Source | `src/CMEToken.sol` |
| Name | `Crypto Market Evolution` |
| Symbol | `CME` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Application contracts | None |
| Launch chain | Ethereum (chain ID `1`) |

## Design and assumptions

The brief is implemented as a standard transferable ERC-20. OpenZeppelin Contracts
v5.0.2 supplies the transfer and approval logic; `CMEToken` adds the fixed metadata
and one constructor mint. `INITIAL_SUPPLY` is a named constant in base units. There
are no constructor calls to outside contracts and no linked external libraries.

There is no owner, administrator, minter role, burn endpoint, tax, pause,
blacklist, seizure, proxy, upgrade mechanism, or post-deployment initialization.
No caller, including the deployer, can increase or decrease the total supply.
Transfers deliver the exact requested amount. The constructor emits one
`Transfer(address(0), deployer, INITIAL_SUPPLY)` event.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
OpenZeppelin ERC-20 custom errors on invalid input or insufficient balance or
allowance. Transfers to the zero address and approvals of the zero spender revert.
Zero-value transfers between nonzero addresses succeed and emit `Transfer`, as
required by [ERC-20](https://eips.ethereum.org/EIPS/eip-20). Self-transfers preserve
balances. Transferring tokens to a contract does not invoke a receiver callback.

`approve` replaces the existing allowance. Finite allowances decrease on spending;
the maximum `uint256` allowance is treated as unlimited and does not decrease.
Successful approvals emit `Approval`. This vendored implementation does not emit
an extra `Approval` when `transferFrom` spends an allowance, so integrations should
read `allowance` for its current value. A failed transfer rolls back the allowance
change as well as all balance changes.

## Build and check

Run from the repository root with Foundry and Solidity **0.8.26** available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x45ea618062a305078d2021d5cddbe855e3a255caf160fa54267862dd672259c2 forge test
forge fmt --check
sha256sum -c dependencies.sha256
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization with 200
runs, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem
permissions. Dependencies are ordinary files under `lib/`, with no submodules,
package installation, RPC, or network needed to build or test once the compiler
and Foundry are installed. See [DEPENDENCIES.md](DEPENDENCIES.md) for provenance.

Tests use isolated local contracts and deterministic test accounts. They do not
read or set environment variables, fork a chain, use a wallet key, or require a
particular execution order. The seed above is passed to Foundry by the shell.

The suite covers metadata, exact supply and mint events, direct and CREATE2 factory
deployment, exact transfers, self/zero/full-balance transfers, finite and unlimited
allowances, revocation, invalid recipients, unauthorized spending, atomic rollback,
absent administrative functions, and rejected native-currency calls. Six fuzz tests
run 1,024 cases each. Three stateful invariants run 256 sequences of 64 calls each,
checking conservation of supply and independently tracked balances and allowances
after transfers, approvals, spending, revocations, and rejected overdrafts.

The local launch-flow test checks the 10%/88%/2% distribution and subsequent claim
and pool-direction token transfers. It is an accounting simulation, not a Uniswap
swap integration test. The supplied protected suite's full PoolManager/launch
harness belongs to the independent verifier and is not included in this project.

## Deployment and operational responsibilities

Deploy `src/CMEToken.sol:CMEToken` directly from its compiled creation bytecode with
empty constructor arguments and zero native-currency value. It needs no script,
configuration addresses, initializer, or follow-up administrative call. The
artifact is `out/CMEToken.sol/CMEToken.json` after building. Do not deploy it behind
a proxy: the constructor is responsible for creating the supply.

The **immediate creator receives every token**. In the intended launch, that is
the launch factory, which must distribute its balance. It is not the transaction's
originating wallet or the requester. A direct wallet deployment instead credits
that wallet. No recipient address is hardcoded in the token. A factory must be
able to transfer its tokens, or the entire supply will remain in that factory.

The network's later manifest/deployment step is responsible for selecting the
`CMEToken` artifact, recording the table above with the exact base-unit supply,
and applying the agreed launch economics. The factory handles the swarm's 10%,
the pool's 88%, and the remaining 2%; the token performs none of these allocations
in its constructor. Pool creation, launch pricing, and the approved remainder
recipient are launch configuration, not token parameters. This project does not
include a launch manifest or perform any broadcast.

### After launch

There are no owner settings or maintenance transactions. The deployer is
responsible for the launch distribution, checking the deployed metadata and
supply, and source verification using the pinned build settings. A separate
independent security review remains a release responsibility; local passing
tests are not an audit. Foundry build, unit/fuzz/invariant tests, and formatting
are the checks used here; Slither and Mythril are not part of this deliverable's
validation.

Holders control their balances and approvals. Prefer allowances limited to the
needed amount; when replacing a nonzero allowance, revoke it first and confirm
that transaction to reduce the standard ERC-20 approval race. Anyone with a live
allowance can spend within that allowance, including after the holder receives
additional tokens. Integrators should read allowance state and handle reverts.

There is no rescue function for tokens sent to this token contract or to other
contracts that cannot return them. Native-currency transfers are rejected by
normal calls; any forcibly delivered native currency is also unrecoverable.
