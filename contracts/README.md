# Binance-Peg BEP20 V2 — recovery of tokens stranded at ZKsync-derived account addresses

Reference implementation for a BEP proposal. Binance is the owner/admin of the upgradeable
Binance-Peg BEP20 tokens on BNB Smart Chain (OpenZeppelin v3.2.0 `TransparentUpgradeableProxy`
in front of `BEP20TokenImplementation`, source: github.com/bnb-chain/canonical-upgradeable-bep20,
archived 2022-09-14). Tokens sent on BSC to an Abstract Global Wallet (AGW) address are stuck: the
address is a ZKsync-style CREATE2 result that no EVM deployment can reproduce (`test_caseA_evmCreate2DoesNotReproduceAddress`),
so nobody can ever put code there on BSC.

`BEP20TokenImplementationV2` adds one owner-gated registry and one permissionless function to the
shared implementation. A claim moves a stranded balance to a destination when, on-chain:

1. the ZKsync factory in the claim has a registered `FactoryScheme` (set by the token owner), and the
   claim's `bytecodeHash` and `keccak256(constructorInput)` equal the values pinned for that factory —
   so the **salt is the only claimant-controlled derivation input**, and under the AGW scheme the salt
   is `keccak256(claimant)`;
2. `keccak256(keccak256("zksyncCreate2") ++ bytes32(factory) ++ salt ++ bytecodeHash ++ keccak256(constructorInput))[12:]`
   equals the stranded address (library `src/ZkCreate2.sol`, checked against two live AGWs);
3. the stranded address has no code on BSC;
4. the claim is not expired and carries the next nonce for that address;
5. an EIP-712 signature over the claim recovers to a signer (no zero address, no high-`s`);
6. for scheme `SALT_IS_KECCAK_OF_INITIAL_OWNER`: `keccak256(abi.encodePacked(signer)) == salt`, i.e. the
   signer is the EOA whose address the AGW factory hashed into the CREATE2 salt.

The balance moves through the inherited V1 `_transfer` (emits `Transfer`), then
`StrandedZkAccountRecovered(stranded, signer, to, amount, factory)` is emitted. `amount == 0` means
the whole balance. Anyone may submit a signed claim (relayer model); the signature is the authority.

Measured inputs come from `../FACTS.md`; the test constants are in `test/Facts.sol`.

### API (names referenced by the BEP text)

```solidity
enum OwnerScheme { NONE, SALT_IS_KECCAK_OF_INITIAL_OWNER }
struct FactoryScheme { OwnerScheme scheme; bytes32 bytecodeHash; bytes32 constructorInputHash; }
struct ZkDeployment  { address factory; bytes32 salt; bytes32 bytecodeHash; bytes constructorInput; }
struct RecoveryClaim { address stranded; address to; uint256 amount; uint256 nonce; uint256 deadline; }

function setZkFactoryScheme(address factory, OwnerScheme scheme, bytes32 bytecodeHash, bytes32 constructorInputHash) external; // onlyOwner; NONE clears
function zkFactoryScheme(address factory) external view returns (OwnerScheme scheme, bytes32 bytecodeHash, bytes32 constructorInputHash);
function recoveryNonce(address stranded) external view returns (uint256);
function recoverStrandedZkAccount(ZkDeployment calldata d, RecoveryClaim calldata c, bytes calldata signature) external;
function zkCreate2Address(ZkDeployment calldata d) external pure returns (address);
function DOMAIN_SEPARATOR() external view returns (bytes32);
function recoveryClaimDigest(RecoveryClaim calldata c) external view returns (bytes32);
bytes32 public constant RECOVERY_CLAIM_TYPEHASH; // keccak256("RecoveryClaim(address stranded,address to,uint256 amount,uint256 nonce,uint256 deadline)")

event ZkFactorySchemeSet(address indexed factory, OwnerScheme scheme, bytes32 bytecodeHash, bytes32 constructorInputHash);
event StrandedZkAccountRecovered(address indexed stranded, address indexed signer, address indexed to, uint256 amount, address factory);
```

Revert strings, in check order: `V2: factory not registered`, `V2: bytecode hash not pinned for factory`,
`V2: constructor input not pinned for factory`, `V2: derivation mismatch`, `V2: stranded address has code`,
`V2: claim expired`, `V2: bad nonce`, `V2: bad signature length`, `V2: bad signature s`, `V2: bad signature v`,
`V2: zero signer`, `V2: signer is not the initial owner`, `V2: nothing to recover`,
`BEP20: transfer amount exceeds balance` (from V1 `_transfer`).

**AGW factory pin (measured):** factory `0x9B947df68D35281C972511B3E7BC875926f26C1A`,
bytecodeHash `0x0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc`,
constructorInputHash = `keccak256(abi.encode(0xaA3633B417483F932969edAef7CC4f1068f6Faa9))` =
**`0x7dc432c80a70eef32157607a2f46e38cf1d957673706133ced678b80fcbf7ca2`**
(`cast keccak 0x000000000000000000000000aa3633b417483f932969edaef7cc4f1068f6faa9`; asserted in
`test_pinnedConstructorInputHashIsKeccakOfEncodedImpl` and in the fork tests).

## Layout

```
foundry.toml                                  solc auto-detect (0.6.12 for src, 0.8.x for tests), optimizer 200 runs, RPC aliases
src/ZkCreate2.sol                             pure library: zkCreate2Address(...) and evmCreate2Address(...)   (pragma >=0.6.0 <0.9.0)
src/BEP20TokenImplementationV2.sol            V1 + recovery; APPEND-ONLY storage                               (pragma 0.6.12)
src/interfaces/IBEP20TokenImplementationV2.sol 0.8 ABI of V2 + proxy admin surface, for tests/integrators
src/vendor/BEP20TokenImplementation.sol       upstream, byte-identical (Apache-2.0, LICENSE-canonical-upgradeable-bep20)
src/vendor/BEP20UpgradeableProxy.sol          upstream, byte-identical
src/vendor/IBEP20.sol                         upstream, byte-identical
lib/openzeppelin-solidity/                    OpenZeppelin v3.2.0 files the upstream imports (MIT), vendored as plain files
lib/forge-std/                                forge-std v1.9.7 (src + licenses), vendored as plain files (no submodules, no remotes)
test/ZkCreate2.t.sol                          derivation unit tests (cases A, B, salt preimage, EVM CREATE2 comparison)
test/RecoveryUnit.t.sol                       local proxy + V1 -> V2 upgrade, every recovery rule incl. pin checks
test/Fork.t.sol                               BSC mainnet fork: real proxy upgraded by its admin, storage preserved, recovery demo, pin checks
GAS.md                                        measured gas
```

### Compiler decision

The upstream project pins solc 0.6.4 (truffle-config) and OpenZeppelin v3.2.0. V2 is written for
**solc 0.6.12** (same 0.6 line, `pragma solidity 0.6.12`) so `forge inspect ... storage-layout` of V1
and V2 come from the same compiler family and the storage argument is a three-line diff (below).
Only the tests and the 0.8 interface use solc 0.8.x. Because V1 declares its state `private`, V2 reads
the token name (EIP-712 domain) and the `amount == 0` balance through external self-calls
(`this.name()`, `this.balanceOf()`) and moves funds through the inherited internal `_transfer`,
instead of editing the vendored file. Signature parsing uses 0.6 calldata slices (`signature[0:32]`)
because `.offset` on calldata bytes needs 0.7+.

## Build and test

Builds and tests run on srv1w (user bibi, Foundry in `~/.foundry/bin`), project synced to `~/pegrecover-build/`:

```sh
rsync -a --delete --exclude out --exclude cache /home/slova/pegrecover/contracts/ srv1w:~/pegrecover-build/
ssh srv1w 'export PATH=$HOME/.foundry/bin:$PATH; cd ~/pegrecover-build && forge build && forge test -vv'
ssh srv1w 'export PATH=$HOME/.foundry/bin:$PATH; cd ~/pegrecover-build && forge test --gas-report'
ssh srv1w 'export PATH=$HOME/.foundry/bin:$PATH; cd ~/pegrecover-build && forge inspect src/vendor/BEP20TokenImplementation.sol:BEP20TokenImplementation storage-layout'
ssh srv1w 'export PATH=$HOME/.foundry/bin:$PATH; cd ~/pegrecover-build && forge inspect src/BEP20TokenImplementationV2.sol:BEP20TokenImplementationV2 storage-layout'
```

No API keys anywhere. The fork test pins **BSC block 129782171** (`Facts.FORK_BLOCK`, read with
`cast block-number` on https://bsc-dataseed.bnbchain.org on 2026-10-26 while writing the test) and
forks through the `bsc` alias in `foundry.toml`.

RPC note (measured 2026-10-26): the bnbchain dataseed nodes are not archive nodes. `cast balance -B`
succeeded at latest-120 and failed with `missing trie node` at latest-200, so a block pinned a few
minutes earlier was already unavailable there and the first fork run failed in `setUp()`. Of the keyless
endpoints probed, `https://bsc-mainnet.public.blastapi.io` served both the pinned block and block
80681471 (the stranding block), `https://bsc-mainnet.gateway.tatum.io` served the pinned block, and
`https://api.zan.top/bsc-mainnet` served it too but is in a trading lane's RPC list on this IP and is
not used. `bsc` therefore points at blastapi; dataseed aliases remain for latest-state work. Endpoints
containing publicnode, tenderly, mevblocker, blockpi or sentio are not used.

### Results — verbatim from srv1w, 2026-10-26

`forge --version`:

```
forge Version: 1.8.3
Commit SHA: cae51ad458f6abb64852b7709eb784352429825d
Build Timestamp: 2026-09-15T10:46:16.519267388Z (1789469176)
Build Profile: dist
solc: 0.6.12 (src), 0.8.28 (test) per build.txt
```

`forge build` (after `forge clean`):

```
Compiling 12 files with Solc 0.6.12
Compiling 26 files with Solc 0.8.28
Solc 0.6.12 finished in 223.93ms
Solc 0.8.28 finished in 878.24ms
Compiler run successful!
Warning: AST source not found for /home/bibi/pegrecover-build/src/vendor/IBEP20.sol
Warning: AST source not found for /home/bibi/pegrecover-build/src/vendor/BEP20TokenImplementation.sol
Warning: AST source not found for /home/bibi/pegrecover-build/src/vendor/BEP20UpgradeableProxy.sol
Warning: AST source not found for /home/bibi/pegrecover-build/src/BEP20TokenImplementationV2.sol
```

`forge test -vv`:

```
No files changed, compilation skipped

Ran 7 tests for test/ZkCreate2.t.sol:ZkCreate2Test
[PASS] test_caseA_evmCreate2DoesNotReproduceAddress() (gas: 3860)
[PASS] test_caseA_saltIsKeccakOfInitialOwner() (gas: 3274)
[PASS] test_caseA_zkCreate2Address() (gas: 3622)
[PASS] test_caseB_saltIsKeccakOfInitialOwner() (gas: 3288)
[PASS] test_caseB_zkCreate2Address() (gas: 3616)
[PASS] test_differentSaltDifferentAddress() (gas: 4151)
[PASS] test_prefixIsKeccakOfZksyncCreate2() (gas: 3073)
Suite result: ok. 7 passed; 0 failed; 0 skipped; finished in 221.14µs (387.16µs CPU time)

Ran 30 tests for test/RecoveryUnit.t.sol:RecoveryUnitTest
[PASS] test_deadlineInclusive() (gas: 159492)
[PASS] test_domainAndDigestMatchEip712() (gas: 82194)
[PASS] test_pinnedConstructorInputHashIsKeccakOfEncodedImpl() (gas: 4416)
[PASS] test_recover_fullBalance_amountZero() (gas: 231980)
Logs:
  gas: relayer->proxy recoverStrandedZkAccount (full balance, local): 119575

[PASS] test_recover_partialAmount_thenRest() (gas: 373619)
[PASS] test_revert_amountExceedsBalance() (gas: 117234)
[PASS] test_revert_badSignatureLength() (gas: 89109)
[PASS] test_revert_badV() (gas: 110200)
[PASS] test_revert_claimedAddressNotDerived() (gas: 80017)
[PASS] test_revert_derivationMismatch() (gas: 77441)
[PASS] test_revert_emptyStrandedBalance() (gas: 116153)
[PASS] test_revert_expired() (gas: 81319)
[PASS] test_revert_malleableSignature() (gas: 110207)
[PASS] test_revert_pinnedInputsCannotRetargetAnotherDerivedAddress() (gas: 201412)
[PASS] test_revert_replay() (gas: 211696)
[PASS] test_revert_schemeClearedToNone() (gas: 143399)
[PASS] test_revert_setZkFactorySchemeByProxyAdmin() (gas: 35373)
[PASS] test_revert_setZkFactorySchemeNotOwner() (gas: 42871)
[PASS] test_revert_setZkFactorySchemeZeroBytecodeHash() (gas: 44849)
[PASS] test_revert_signatureBoundToClaimFields() (gas: 116074)
[PASS] test_revert_strandedAddressHasCode() (gas: 83753)
[PASS] test_revert_unregisteredFactory() (gas: 76111)
[PASS] test_revert_wrongBytecodeHash() (gas: 74357)
[PASS] test_revert_wrongConstructorInput() (gas: 80784)
[PASS] test_revert_wrongNonce() (gas: 83253)
[PASS] test_revert_wrongSigner() (gas: 131135)
[PASS] test_revert_zeroSigner() (gas: 93658)
[PASS] test_setZkFactorySchemeEmits() (gas: 134454)
[PASS] test_upgradePreservedV1State() (gas: 194246)
[PASS] test_zkCreate2AddressView() (gas: 39411)
Suite result: ok. 30 passed; 0 failed; 0 skipped; finished in 1.44ms (8.89ms CPU time)

Ran 9 tests for test/Fork.t.sol:ForkTest
[PASS] test_fork_caseA_claimPassesEveryCheckExceptSignature() (gas: 2336524)
[PASS] test_fork_caseA_isStrandedAtForkBlock() (gas: 37888)
[PASS] test_fork_caseA_randomKeyRejected() (gas: 2421894)
[PASS] test_fork_caseA_wrongBytecodeHashRejected() (gas: 2356631)
[PASS] test_fork_caseA_wrongConstructorInputRejected() (gas: 2360496)
[PASS] test_fork_recoverFreshAgwAddress() (gas: 2707941)
Logs:
  gas: relayer->proxy recoverStrandedZkAccount (full balance, fork): 119496

[PASS] test_fork_registerSchemeOnlyByTokenOwner() (gas: 2212624)
[PASS] test_fork_upgradeOnlyByProxyAdmin() (gas: 2171895)
[PASS] test_fork_upgradePreservesStorage() (gas: 2448173)
Suite result: ok. 9 passed; 0 failed; 0 skipped; finished in 1.03s (1.88s CPU time)

Ran 3 test suites in 1.03s (1.03s CPU time): 46 tests passed, 0 failed, 0 skipped (46 total tests)
```

**46 passed, 0 failed, 0 skipped** (7 derivation, 30 unit, 9 fork). Gas: see `GAS.md`
(`recoverStrandedZkAccount` 80,173 gas in the implementation frame on the fork; 119,496 gas from the relayer's frame through the proxy).

## Storage-layout compatibility

`forge inspect <Contract> storage-layout` on srv1w, both compiled with solc 0.6.12. The diff shows only
appended slots; every V1 slot, offset and type is unchanged. `Initializable` (OZ 3.2.0) occupies slot 0 in both.

```diff
--- layout-v1.txt	2026-10-25 22:18:59.518234157 +0000
+++ layout-v2.txt	2026-10-25 22:18:59.518293829 +0000
@@ -8,3 +8,6 @@
 slot  6 offset  0 bytes    1  _decimals          uint8
 slot  6 offset  1 bytes   20  _owner             address
 slot  6 offset 21 bytes    1  _mintable          bool
+slot  7 offset  0 bytes   32  _zkFactoryScheme   mapping(address => struct BEP20TokenImplementationV2.FactoryScheme)
+slot  8 offset  0 bytes   32  _recoveryNonce     mapping(address => uint256)
+slot  9 offset  0 bytes 1536  __gapV2            uint256[48]
```

Full V1 layout:

```
slot  0 offset  0 bytes    1  _initialized       bool
slot  0 offset  1 bytes    1  _initializing      bool
slot  1 offset  0 bytes   32  _balances          mapping(address => uint256)
slot  2 offset  0 bytes   32  _allowances        mapping(address => mapping(address => uint256))
slot  3 offset  0 bytes   32  _totalSupply       uint256
slot  4 offset  0 bytes   32  _name              string
slot  5 offset  0 bytes   32  _symbol            string
slot  6 offset  0 bytes    1  _decimals          uint8
slot  6 offset  1 bytes   20  _owner             address
slot  6 offset 21 bytes    1  _mintable          bool
```

Full V2 layout:

```
slot  0 offset  0 bytes    1  _initialized       bool
slot  0 offset  1 bytes    1  _initializing      bool
slot  1 offset  0 bytes   32  _balances          mapping(address => uint256)
slot  2 offset  0 bytes   32  _allowances        mapping(address => mapping(address => uint256))
slot  3 offset  0 bytes   32  _totalSupply       uint256
slot  4 offset  0 bytes   32  _name              string
slot  5 offset  0 bytes   32  _symbol            string
slot  6 offset  0 bytes    1  _decimals          uint8
slot  6 offset  1 bytes   20  _owner             address
slot  6 offset 21 bytes    1  _mintable          bool
slot  7 offset  0 bytes   32  _zkFactoryScheme   mapping(address => struct BEP20TokenImplementationV2.FactoryScheme)
slot  8 offset  0 bytes   32  _recoveryNonce     mapping(address => uint256)
slot  9 offset  0 bytes 1536  __gapV2            uint256[48]
```

`FactoryScheme` value layout inside the slot-7 mapping (from `forge inspect --json`): `scheme` at
word 0 (1 byte), `bytecodeHash` at word 1, `constructorInputHash` at word 2; 96 bytes per entry.
Slot 7 was a `mapping(address => OwnerScheme)` in the first (never deployed) draft of V2 and now holds
`mapping(address => FactoryScheme)`; since no V2 has been deployed, slot 7 is unused on-chain and the
change is free.

V2 adds `_zkFactoryScheme` (slot 7), `_recoveryNonce` (slot 8) and a 48-word gap (slots 9..56) so a
future V3 can append again without touching anything the proxy already holds. V2 adds no constructor
logic and no new `initialize`; `upgradeTo` (not `upgradeToAndCall`) is enough. The fork test
`test_fork_upgradePreservesStorage` reads name, symbol, decimals, totalSupply, getOwner, the Binance hot
wallet balance and the stranded balance before and after the real upgrade and asserts equality, plus
`balanceOf(0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86) == 19998e18`.

## Security notes

- **Initial-owner binding only.** The AGW factory hashes the *initial* k1 owner into the salt. An AGW
  whose owner was rotated after deployment is still recoverable only by the initial owner's key; the
  current owner on Abstract is not consulted (and for case A was not read — unmeasured). A scheme for
  "current owner" would need a cross-chain proof and is out of scope of this V2; the `OwnerScheme` enum
  and per-factory registry leave room for one.
- **Stranded address must be code-less on BSC** (`extcodesize == 0`). If code ever appears there, that
  code owns the balance and recovery is refused. No BSC fork has ever written code to a user address
  (FACTS.md), and the ZKsync derivation cannot be reproduced by EVM CREATE/CREATE2.
- **Derivation is verified, not trusted, and its inputs are pinned.** The token owner registers, per
  factory, the account bytecode hash and the hash of the constructor input that factory uses. A claim
  must match both (`V2: bytecode hash not pinned for factory`, `V2: constructor input not pinned for factory`;
  `test_revert_wrongBytecodeHash`, `test_revert_wrongConstructorInput`, `test_fork_caseA_wrongBytecodeHashRejected`,
  `test_fork_caseA_wrongConstructorInputRejected`), then the contract recomputes the ZKsync CREATE2 address
  and compares it with `c.stranded`. With the salt fixed to `keccak256(signer)` by the scheme and the other
  two inputs fixed by the pin, **a signer can only ever target the one address they would own under that
  factory**; no multi-target grinding surface (vary bytecodeHash/constructorInput to land on someone
  else's address) remains — `test_revert_pinnedInputsCannotRetargetAnotherDerivedAddress` tries both the
  unpinned-input route and the pinned route against a funded victim address and both revert. A claim
  naming any other address (e.g. a real holder) fails with `derivation mismatch` (`test_revert_claimedAddressNotDerived`).
- **Relayer model.** Anyone may submit; the EIP-712 signature (domain: `name()`, version `"1"`, chainId 56,
  verifyingContract = proxy) binds `stranded`, `to`, `amount`, `nonce`, `deadline`. A relayer cannot
  redirect the payout (`test_revert_signatureBoundToClaimFields`). Replay is blocked by the per-address
  nonce; staleness by `deadline` (inclusive). High-`s` signatures, `v` outside {27, 28}, non-65-byte
  signatures and `ecrecover` returning zero are rejected.
- **Scope of authority.** Binance's owner key only registers/clears a factory's scheme and pins
  (`setZkFactoryScheme`); it cannot move anyone's balance. A wrong pin disables recovery for that factory
  (claims revert); it cannot redirect funds. The proxy admin only swaps implementations and, per OZ 3.2.0, cannot
  call token functions at all (`test_revert_setZkFactorySchemeByProxyAdmin`). Nonce state and scheme
  registry are per proxy, i.e. per token.
- **Supply is unchanged** by a recovery; it is a balance move, not a mint (asserted in both happy paths).
- Not covered: tokens stranded at non-ZKsync smart-account addresses, or at AGW addresses that have
  since received code on BSC (none observed; unmeasured in general).

## Upgrade procedure (Binance-Peg USDC, measured addresses)

The proxy at `0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d` is an OZ 3.2.0 `TransparentUpgradeableProxy`.
Its admin slot holds an **EOA**, `0xD2f93484f2D319194cBa95C5171B18C1d8cfD6C4` (nonce 175 per FACTS.md),
not a ProxyAdmin contract, so the admin calls the proxy directly. The token owner (`getOwner()`) is a
different address, `0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d`.

1. Deploy `BEP20TokenImplementationV2` (solc 0.6.12, optimizer 200 runs, no constructor args) and note
   its address `V2`. Verify `forge inspect` layouts as above.
2. Admin EOA `0xD2f9...D6C4` -> proxy: `upgradeTo(V2)`
   (`cast send 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d "upgradeTo(address)" $V2 --from 0xD2f93484f2D319194cBa95C5171B18C1d8cfD6C4`).
   OZ 3.2.0 requires `V2` to have code and emits `Upgraded(V2)`. No initializer call is needed.
   Reproduced on the fork in `test_fork_upgradePreservesStorage`; a non-admin caller reverts (`test_fork_upgradeOnlyByProxyAdmin`).
3. Token owner `0xF68a...f62d` -> proxy:
   `setZkFactoryScheme(0x9B947df68D35281C972511B3E7BC875926f26C1A, 1, 0x0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc, 0x7dc432c80a70eef32157607a2f46e38cf1d957673706133ced678b80fcbf7ca2)`
   (1 = `SALT_IS_KECCAK_OF_INITIAL_OWNER`; the AGW `AccountFactory`; its account bytecode hash; keccak256 of
   `abi.encode(AGW impl 0xaA36...Faa9)`). Emits `ZkFactorySchemeSet(factory, 1, bytecodeHash, constructorInputHash)`.
   Reproduced in `test_fork_recoverFreshAgwAddress`; a non-owner reverts (`test_fork_registerSchemeOnlyByTokenOwner`).
4. Each affected user signs an EIP-712 `RecoveryClaim` with the AGW's initial-owner key
   (`recoveryClaimDigest(c)` returns the exact digest; `DOMAIN_SEPARATOR()` the domain) and anyone submits
   `recoverStrandedZkAccount({factory: 0x9B94...6C1A, salt: keccak256(owner), bytecodeHash: 0x0100003316a9...85bc, constructorInput: abi.encode(0xaA3633B417483F932969edAef7CC4f1068f6Faa9)}, claim, signature)`.
   `bytecodeHash` and `constructorInput` must hash to the pinned values from step 3, so for a given signer
   exactly one `stranded` address can pass.
5. Other Binance-Peg tokens: repeat step 2 per proxy with the same `V2` address if that proxy's current
   implementation is the same V1 contract; whether other Binance-Peg proxies share this implementation
   and admin was not read (unmeasured).

Case A (`0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`, 19,998 Binance-Peg USDC) passes every check on
the fork except the signature, which only the initial owner `0x07c65fe9f29a86b937604fa8d20a3fae19d7be48`
can produce (`test_fork_caseA_claimPassesEveryCheckExceptSignature` — registered with the real pinned values —
and `test_fork_caseA_randomKeyRejected`).
