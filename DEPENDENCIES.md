# Vendored dependencies

All dependency source files and their upstream license texts are included as
ordinary files. Neither Git submodules nor a dependency download step is used.

| Dependency | Release | Exact upstream commit | Included files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20, IERC20, IERC20Metadata, IERC6093 errors, Context, MIT license |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/`, MIT and Apache-2.0 licenses |

OpenZeppelin is the production contract dependency. Forge Standard Library is
used only by tests. Source files were copied without modification from archives
of the commits above, including their SPDX headers. Only the OpenZeppelin files
needed by the token and their transitive imports are vendored.

`dependencies.sha256` records every included dependency file. Check the vendored
contents without network access using `sha256sum -c dependencies.sha256`.
