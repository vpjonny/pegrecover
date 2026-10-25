# Adversarial review — BEP20TokenImplementationV2 (ZK-stranded recovery)

Reviewed 2026-10-26 against commit `4705556` of this tree. Scope: `src/BEP20TokenImplementationV2.sol`,
`src/ZkCreate2.sol`, `src/vendor/BEP20TokenImplementation.sol`, `src/vendor/BEP20UpgradeableProxy.sol`,
`test/*`, the BEP text in `../bep/` and `../FACTS.md`. The view below was formed from the code first;
README/BEP claims were compared afterwards (section "README and spec vs code").

Everything marked **PoC** is demonstrated by a passing test in `test/Review.t.sol` (24 tests, all pass on
srv1w, forge 1.8.3, solc 0.6.12/0.8.28; full suite 70/70). Everything marked **concern** is reasoning only.

Toolchain facts gathered while reviewing (srv1w, 2026-10-26, blastapi RPC at block 129782171):

- `forge inspect` storage layouts of V1 and V2 (solc 0.6.12): identical for slots 0..6; V2 appends 7, 8, 9..56.
- Live Binance-Peg USDC proxy `0x8AC7…580d`: slot 0 = `0x…01` (`_initialized`), slot 6 =
  `0x…01 f68a4b64…fef62d 12` (mintable=1 | owner | decimals=18), `mintable()==true`, `name()=="USD Coin"`.
- Deployed V1 implementation `0xBA5F…0B5C`: CBOR metadata says **solc 0.6.4**; runtime 5,066 bytes
  (5,013 without metadata) vs the vendored source compiled at 0.6.12: 5,006 (4,953). Same selector set.
  Layout equality is therefore proven by the live slot reads and the fork tests, not by bytecode identity.
- V2 runtime 9,462 bytes (EIP-170 limit 24,576). No selector of V2 equals a proxy admin selector.

## Verdict

No Critical, High or Medium finding. I could not construct any input that moves a balance from an address
that is not `zkCreate2(factory, keccak256(signer), pinnedBytecodeHash, pinnedConstructorInputHash)` with
`extcodesize == 0`, nor any input that bricks the token, re-initialises it, or alters an existing holder's
balance/allowance. The three Low findings are behaviours that are per spec but worth a line in the BEP or a
cheap guard; the rest is Info.

## Findings

### L-1 (Low) — a full-balance claim (`amount == 0`) is a bearer sweep of future deposits until `deadline`

- Location: `recoverStrandedZkAccount`, `if (amount == 0) amount = this.balanceOf(c.stranded);`
- PoC: `test_review_fullBalanceClaimSweepsLaterDeposits` — signer signs `amount=0`; 5,000 more tokens land
  at the stranded address after signing; execution moves 6,000 to `to`.
- Why it matters: the signature is a standing instruction; whoever holds it (relayer, phishing site) chooses
  the execution moment and sweeps whatever is there. Exposure is limited to the signer's own stranded address
  and to the signed `to`, so no third party gains anything — hence Low.
- Fix: keep the semantics (the spec's §6 rationale is valid) but state in §8 that `amount == 0` claims
  should carry short deadlines, and have wallet/relayer UIs default to an explicit amount with `deadline`
  of hours, not days.

### L-2 (Low) — `to` may be the token proxy itself (or any other contract); funds are then unrecoverable

- Location: `recoverStrandedZkAccount` → `_transfer(c.stranded, c.to, amount)`; only `to != 0` is enforced.
- PoC: `test_review_toEqualsProxyStrandsAgain` — a claim with `to = proxy` succeeds; the proxy has code so
  it can never itself be a recovery subject. Also `test_review_toEqualsStrandedIsNoopButConsumesNonce`
  (`to == stranded`: no-op that consumes a nonce and emits `Transfer(s, s, amt)`).
- Fix (optional, one line): `require(c.to != address(this) && c.to != c.stranded, "V2: bad destination")`.
  Both are signer mistakes, not attacks; if the implementers prefer "the signature is the authority", leave
  the code and add a wallet-side warning.

### L-3 (Low) — token owner can cancel or revive every outstanding signed claim via the registry

- Location: `setZkFactoryScheme` (clear to `NONE` or re-pin).
- PoC: `test_review_ownerCanCancelOutstandingClaimsByClearingRegistry` — a valid signed claim reverts after
  the owner clears the AGW entry and succeeds again, with the same bytes, after re-registration (nonce was
  never consumed). `test_review_ownerRepinBreaksClaimsOnly` — a re-pin only makes claims revert; ordinary
  token functions are unaffected.
- Why it matters: recovery availability is at the token owner's discretion at every moment. This is the
  BEP's stated design (§5.4, §8 "Registry governance"), and the owner can already `mint`, so it is not a new
  trust assumption — but a signer should know a signed claim is not vested.
- Fix: none in code; one sentence in §5.6 ("a signed claim remains valid after a registry reset and re-
  registration unless its nonce was consumed or its deadline passed").

### I-1 (Info) — raw implementation contract is initialisable by anyone

- PoC: `test_review_rawImplementationInitializableByAnyone_noEffectOnProxy` — an attacker calls
  `initialize` on the V2 implementation address directly, becomes owner **of the implementation's own
  storage** and can write its registry; the proxy is untouched. Same exposure as the live V1 (`0xBA5F…`).
  Cosmetic only; optionally call `initialize` on the implementation right after deployment.

### I-2 (Info) — deployed V1 is solc 0.6.4, vendored copy compiles with 0.6.12

- Runtime bytecode differs (see toolchain facts). The storage argument in README rests on compiling the
  vendored *source* with 0.6.12 and on fork reads; it is sound because the 0.6 line never changed layout
  rules, and because the live slots 0 and 6 read exactly as the layout predicts (verified above and in
  `test_reviewFork_slot0MintableAllowanceSurviveUpgrade_initializeDead`). The README's "byte-identical"
  claim refers to the source vs the archived upstream repository; I did not fetch upstream to re-verify it.

### I-3 (Info) — spec/code ordering and one revert string not listed

- The BEP §5.5 lists `c.to != 0` as step 3 and nonce increment as step 10; the code relies on V1
  `_transfer`'s `"BEP20: transfer to the zero address"` and increments the nonce before signature recovery.
  Both are permitted by §5.5's "MAY reorder" sentence and are invisible on-chain (a revert undoes the
  write). The README revert-string list omits `BEP20: transfer to the zero address`.

### I-4 (Info) — `test_fork_upgradeOnlyByProxyAdmin` passes on any revert

- It uses bare `vm.expectRevert()`. The real reason is that a non-admin `upgradeTo` falls through the
  TransparentUpgradeableProxy into V1, which has no such selector and no fallback → empty revert. The test
  does assert the implementation slot is unchanged afterwards, so it is not vacuous; just imprecise.

### I-5 (Info) — V2's two self-calls depend on the proxy fallback admitting `msg.sender == proxy`

- `this.name()` and `this.balanceOf()` are STATICCALLs to the proxy, which pass OZ 3.2
  `_beforeFallback` because the proxy is not its own admin. If an admin ever ran `changeAdmin(proxy)` the
  V2 paths (`recoverStrandedZkAccount`, `DOMAIN_SEPARATOR`, `recoveryClaimDigest`) would revert while V1
  functions keep working. That `changeAdmin` would also permanently lock the proxy's admin functions, so
  it is not a realistic state. No action.

### I-6 (Info) — solc 0.6.12 known-bug list

- Checked against the published list for 0.6.12: `DynamicArrayCleanup`, `EmptyByteArrayCopy`,
  `NestedCalldataArrayAbiReencodingSizeValidation`, `AbiReencodingHeadOverflowWithStaticArrayCleanup`,
  `ABIDecodeTwoDimensionalArrayMemory`, `SignedImmutables`, `KeccakCaching`. None of the triggering
  patterns (storage byte arrays, nested dynamic arrays in calldata re-encoding, immutables, abi.decode of
  2-D arrays) occur in V2. The ABIEncoderV2 calldata decoder's enum validation is confirmed by PoC
  `test_review_enumOutOfRangeRejected` (scheme value 2 rejected at the ABI boundary; even if it were not,
  the recover path has an explicit `revert("V2: unknown scheme")`). Dirty high bits in a calldata address
  field cannot move funds either way (`test_review_dirtyCalldataAddressDoesNotMove`).

### I-7 (Info, concern) — usability of the signing step for AGW initial owners

- The claimant must produce a plain EIP-712 signature (chainId 56 in the domain) with the k1 key that was
  the AGW's initial owner. For AGW users that key is a Privy embedded wallet; FACTS.md records that the AGW
  SDK refuses chain 56 for transactions. Whether the embedded signer will sign typed data whose domain
  names chain 56 is unmeasured. Not a contract issue; it decides whether case A can actually be exercised.

## Checklist

1. **Storage layout.** Yes. `forge inspect` (0.6.12) for V1 and V2: slot 0 `_initialized`/`_initializing`,
   1 `_balances`, 2 `_allowances`, 3 `_totalSupply`, 4 `_name`, 5 `_symbol`, 6 `_decimals@0`/`_owner@1`/
   `_mintable@21`; V2 appends 7 `_zkFactoryScheme` (96-byte struct: scheme word, bytecodeHash, cih), 8
   `_recoveryNonce`, 9..56 `__gapV2`. Inheritance order is unchanged (`Context, IBEP20, Initializable`;
   Context/IBEP20 have no state). Live proxy slots 0 and 6 match. PoC `test_review_rawStorageSlots`
   reads every one of these slots raw through the proxy, including the mapping/struct positions.
   Proxy storage is EIP-1967 hashed slots (`0x3608…bbc`, `0xb531…103`) — no overlap with 0..56.
2. **Reachable addresses.** Only `zkCreate2(d)` with pinned `bytecodeHash`/`cih` and `salt == keccak(signer)`.
   `address(0)`: unreachable (`test_review_zeroStrandedUnreachable`; `_transfer` would also refuse).
   Precompiles: `extcodesize == 0` but not derivable (160-bit preimage). EIP-7702/BEP-441 designator
   (23 bytes) blocks a claim (`test_review_eip7702DesignatorBlocksClaim`); it cannot be planted by a third
   party because the stranded address has no private key. Proxy itself and token owner: unreachable
   (`test_review_proxyItselfAndOwnerUnreachable`); the proxy additionally has code. `address(this)` as
   `stranded` fails derivation, and has code.
3. **Signature.** Domain = (`this.name()`, `"1"`, `chainid()`, `address(this)`); through the proxy
   `address(this)` is the proxy, confirmed by `test_domainAndDigestMatchEip712` and by the fork match of the
   BEP's stated USDC separator `0xfc877ab7…27b9` (`test_reviewFork_domainSeparatorMatchesSpec`).
   Typehash constant equals `keccak256("RecoveryClaim(address stranded,address to,uint256 amount,uint256 nonce,uint256 deadline)")`
   (asserted in RecoveryUnit) and `abi.encode` field order matches the struct. Malleability: `s ≤ n/2`,
   `v ∈ {27,28}`, length 65, zero signer rejected (existing tests). Same-name tokens: separators differ by
   `verifyingContract`; a signature for proxy A fails on proxy B with the same `name()`
   (`test_review_noReplayAcrossProxiesWithSameName`). Cross-chain: `chainid()` read at call time
   (`test_review_noCrossChainReplay`).
4. **Nonce/deadline.** Replay blocked (nonce); a third party cannot burn a nonce — a failed claim reverts
   the write (`test_review_thirdPartyCannotBurnNonce`); front-running an identical claim only changes who
   pays gas (`test_review_relayerFrontrunSameClaim_victimStillPaid`); topping up the stranded balance does
   not block an exact-amount claim (`test_review_topUpDoesNotBlockExactAmountClaim`). No way for a third
   party to block a claim short of the owner clearing the registry (L-3). Reentrancy: the only external
   calls are two STATICCALLs to self (`name`, `balanceOf`); `_transfer` has no hooks; nonce is written
   before any of them.
5. **amount == 0 / partial / supply / events.** `0` = full balance at execution (L-1); partial claims
   consume one nonce each and the remainder needs the next nonce (existing test); `amount > balance`
   reverts in `_transfer`; `totalSupply` invariant (`test_review_supplyInvariantAndEventAmount`, plus
   both happy paths); `Transfer(stranded, to, executedAmount)` carries the executed amount, not the signed 0.
6. **Owner powers.** `setZkFactoryScheme` is `onlyOwner`; the proxy admin cannot reach it. A malicious
   owner can register any factory/pins, but to drain a specific funded address X it would need a signer `k`
   and tuple with `keccak(prefix‖factory‖keccak(k)‖bh‖cih) == X` — a 160-bit preimage
   (`test_review_ownerRegistryCannotTargetFundedAddress`). The owner's new powers are: enabling claims
   for factories that do not actually bind salt to owner (spec §8), and cancelling/reviving claims (L-3).
   Both are weaker than `mint()`, which the owner holds on USDC (`mintable()==true`, measured;
   `test_reviewFork_ownerMintUnchanged`).
7. **Upgrade path.** `upgradeTo` by the proxy admin suffices; V2 adds no initializer and needs none (new
   mappings start zero). `initialize` stays dead after the upgrade on the live proxy
   (`test_reviewFork_slot0MintableAllowanceSurviveUpgrade_initializeDead`, revert
   `Initializable: contract is already initialized`), `mintable()` and an allowance set pre-upgrade survive.
   Selector clash: none of V2's 8 new selectors (`cedc12cb`, `d564e76a`, `0b678e50`, `49bcad0a`,
   `c843ac10`, `3644e515`, `149827ce`, `85d984ec`) equals `f851a440/5c60da1b/8f283970/3659cfe6/4f1ef286`
   (`test_review_noSelectorClashWithProxy`); with OZ 3.2 a clash would only matter for admin callers anyway.
8. **Gas/DoS.** No loops; `keccak256(d.constructorInput)` is bounded by calldata; worst case is a revert
   at 3.3k gas, success ~80k in the implementation frame (GAS.md numbers reproduced on this run:
   119,575 local / 119,496 fork from the relayer frame). No revert-on-success path.
9. **Tests vs README claims.** The README's enumerated claims each map to a test that asserts the
   specific revert string or value; none pass vacuously. Gaps found and filled here: slot 0 / `mintable` /
   allowance across the real upgrade, the BEP's literal USDC domain separator, same-name replay,
   cross-chain replay, 7702 designator, raw-slot layout, enum range, dirty calldata, third-party nonce
   burn, registry cancel/revive. Weak spot noted: I-4 (bare `expectRevert`).

## README and spec vs code

- README check order and revert strings match the code except the omitted `_transfer` zero-address string (I-3).
- BEP §5.3 domain separator for USDC: matches on fork. §5.2 formula: matches `ZkCreate2` and cases A/B.
- BEP §5.5 "the function makes no external calls": strictly, it makes two STATICCALLs to itself
  (`this.name()`, `this.balanceOf()`); suggest "no calls to other contracts".
- BEP §8 "set of addresses any one key can ever claim under a factory has exactly one member": holds given
  pinning; confirmed by `test_revert_pinnedInputsCannotRetargetAnotherDerivedAddress` and
  `test_review_ownerRegistryCannotTargetFundedAddress`.
- FACTS line "Factory ENFORCES salt == keccak(initialOwner)" (measured on Era) closes the one design risk
  the BEP flags as unmeasured in §5.4/§8; the BEP text should be updated to cite it.

## Files

- `REVIEW.md` (this file)
- `test/Review.t.sol` — 21 unit + 3 fork PoCs, all passing; run with
  `forge test --match-path test/Review.t.sol -vv` (fork tests use the `bsc` alias).

By KURWA claude
