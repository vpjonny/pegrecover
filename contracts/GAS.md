# Gas — `recoverStrandedZkAccount`

Measured on srv1w with `forge 1.8.3` (solc 0.6.12 for the implementation, optimizer on, 200 runs),
2026-10-26, from the run whose transcript is in README.md (pinned-registry version, 46 tests).
Nothing below is estimated.

## Headline numbers

| Measurement | Gas | How measured |
|---|---|---|
| Implementation frame, full-balance recovery, **BSC fork** (`test_fork_recoverFreshAgwAddress`) | **80,173** | `forge test --match-test test_fork_recoverFreshAgwAddress --gas-report`, row `recoverStrandedZkAccount` |
| Implementation frame, full-balance recovery, local proxy (`test_recover_fullBalance_amountZero`) | 80,173 | same, local test |
| Implementation frame, partial then remainder (`test_recover_partialAmount_thenRest`) | 78,058 (first, partial) / 45,990 (second, warm nonce + recipient) | same |
| Caller frame: relayer -> proxy -> V2, full balance, **BSC fork** | **119,496** | `gasleft()` delta around the external call inside the test (logged) |
| Caller frame: relayer -> proxy -> V2, full balance, local | 119,575 | same |
| Earliest revert (`factory not registered`) | 3,278 | `--gas-report` Min column over 29 calls |
| `setZkFactoryScheme` (register: 3 storage words) | 71,431 | `--gas-report` Max/Median |
| V2 deployment | 2,097,604 gas / 9,494 bytes | `--gas-report` |

The pinned registry costs +4,712 gas per recovery versus the unpinned first version (75,461 -> 80,173):
two extra cold `SLOAD`s of the pinned hashes plus the `keccak256(constructorInput)`.

Caller-frame figures include the TransparentUpgradeableProxy dispatch and the two external self-calls
(`this.name()` for the EIP-712 domain, `this.balanceOf()` for the `amount == 0` path). They exclude the
21,000 intrinsic transaction gas and calldata gas, so a real transaction costs more than 119,496; that
total was not measured. BNB cost at a given gas price was not measured.

## Raw `forge test --gas-report` (all 46 tests)

```
╭------------------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| src/BEP20TokenImplementationV2.sol:BEP20TokenImplementationV2 Contract |                 |       |        |       |         |
+=============================================================================================================================+
| Deployment Cost                                                        | Deployment Size |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                2097604 |            9494 |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                        |                 |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                                          | Min             | Avg   | Median | Max   | # Calls |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| DOMAIN_SEPARATOR                                                       |            7921 |  7921 |   7921 |  7921 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| RECOVERY_CLAIM_TYPEHASH                                                |             273 |   273 |    273 |   273 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| balanceOf                                                              |            2686 |  2686 |   2686 |  2686 |      29 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| decimals                                                               |            2392 |  2392 |   2392 |  2392 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| getOwner                                                               |            2448 |  2448 |   2448 |  2448 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| mintable                                                               |            2446 |  2446 |   2446 |  2446 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| name                                                                   |            2974 |  2974 |   2974 |  2974 |      47 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoverStrandedZkAccount                                               |            3278 | 33249 |  40787 | 80173 |      29 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoveryClaimDigest                                                    |            9069 |  9069 |   9069 |  9069 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoveryNonce                                                          |            2642 |  2642 |   2642 |  2642 |       6 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setZkFactoryScheme                                                     |            2750 | 64994 |  71431 | 71431 |      40 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| symbol                                                                 |            3039 |  3039 |   3039 |  3039 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| totalSupply                                                            |            2440 |  2440 |   2440 |  2440 |       5 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| transfer                                                               |           30146 | 30146 |  30146 | 30146 |      32 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| zkCreate2Address                                                       |            1501 |  1501 |   1501 |  1501 |       4 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| zkFactoryScheme                                                        |            6953 |  6953 |   6953 |  6953 |       7 |
╰------------------------------------------------------------------------+-----------------+-------+--------+-------+---------╯
╭---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╮
| src/vendor/BEP20TokenImplementation.sol:BEP20TokenImplementation Contract |                 |        |        |        |         |
+==================================================================================================================================+
| Deployment Cost                                                           | Deployment Size |        |        |        |         |
|---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                   1134605 |            5038 |        |        |        |         |
|---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
|                                                                           |                 |        |        |        |         |
|---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| Function Name                                                             | Min             | Avg    | Median | Max    | # Calls |
|---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------|
| initialize                                                                |          137536 | 137536 | 137536 | 137536 |      30 |
╰---------------------------------------------------------------------------+-----------------+--------+--------+--------+---------╯
╭---------------------------------------------------------------------+-----------------+-------+--------+--------+---------╮
| src/vendor/BEP20UpgradeableProxy.sol:BEP20UpgradeableProxy Contract |                 |       |        |        |         |
+===========================================================================================================================+
| Deployment Cost                                                     | Deployment Size |       |        |        |         |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
|                                                              598517 |            2767 |       |        |        |         |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
|                                                                     |                 |       |        |        |         |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| Function Name                                                       | Min             | Avg   | Median | Max    | # Calls |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| fallback                                                            |            3429 | 45289 |  42247 | 113338 |     163 |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| upgradeTo                                                           |           32691 | 32691 |  32691 |  32691 |      30 |
╰---------------------------------------------------------------------+-----------------+-------+--------+--------+---------╯
```

## Per-test gas snapshot (`forge snapshot`)

```
ForkTest:test_fork_caseA_claimPassesEveryCheckExceptSignature() (gas: 2336524)
ForkTest:test_fork_caseA_isStrandedAtForkBlock() (gas: 37888)
ForkTest:test_fork_caseA_randomKeyRejected() (gas: 2421894)
ForkTest:test_fork_caseA_wrongBytecodeHashRejected() (gas: 2356631)
ForkTest:test_fork_caseA_wrongConstructorInputRejected() (gas: 2360496)
ForkTest:test_fork_recoverFreshAgwAddress() (gas: 2707941)
ForkTest:test_fork_registerSchemeOnlyByTokenOwner() (gas: 2212624)
ForkTest:test_fork_upgradeOnlyByProxyAdmin() (gas: 2171895)
ForkTest:test_fork_upgradePreservesStorage() (gas: 2448173)
RecoveryUnitTest:test_deadlineInclusive() (gas: 159492)
RecoveryUnitTest:test_domainAndDigestMatchEip712() (gas: 82194)
RecoveryUnitTest:test_pinnedConstructorInputHashIsKeccakOfEncodedImpl() (gas: 4416)
RecoveryUnitTest:test_recover_fullBalance_amountZero() (gas: 231980)
RecoveryUnitTest:test_recover_partialAmount_thenRest() (gas: 373619)
RecoveryUnitTest:test_revert_amountExceedsBalance() (gas: 117234)
RecoveryUnitTest:test_revert_badSignatureLength() (gas: 89109)
RecoveryUnitTest:test_revert_badV() (gas: 110200)
RecoveryUnitTest:test_revert_claimedAddressNotDerived() (gas: 80017)
RecoveryUnitTest:test_revert_derivationMismatch() (gas: 77441)
RecoveryUnitTest:test_revert_emptyStrandedBalance() (gas: 116153)
RecoveryUnitTest:test_revert_expired() (gas: 81319)
RecoveryUnitTest:test_revert_malleableSignature() (gas: 110207)
RecoveryUnitTest:test_revert_pinnedInputsCannotRetargetAnotherDerivedAddress() (gas: 201412)
RecoveryUnitTest:test_revert_replay() (gas: 211696)
RecoveryUnitTest:test_revert_schemeClearedToNone() (gas: 143399)
RecoveryUnitTest:test_revert_setZkFactorySchemeByProxyAdmin() (gas: 35373)
RecoveryUnitTest:test_revert_setZkFactorySchemeNotOwner() (gas: 42871)
RecoveryUnitTest:test_revert_setZkFactorySchemeZeroBytecodeHash() (gas: 44849)
RecoveryUnitTest:test_revert_signatureBoundToClaimFields() (gas: 116074)
RecoveryUnitTest:test_revert_strandedAddressHasCode() (gas: 83753)
RecoveryUnitTest:test_revert_unregisteredFactory() (gas: 76111)
RecoveryUnitTest:test_revert_wrongBytecodeHash() (gas: 74357)
RecoveryUnitTest:test_revert_wrongConstructorInput() (gas: 80784)
RecoveryUnitTest:test_revert_wrongNonce() (gas: 83253)
RecoveryUnitTest:test_revert_wrongSigner() (gas: 131135)
RecoveryUnitTest:test_revert_zeroSigner() (gas: 93658)
RecoveryUnitTest:test_setZkFactorySchemeEmits() (gas: 134454)
RecoveryUnitTest:test_upgradePreservedV1State() (gas: 194246)
RecoveryUnitTest:test_zkCreate2AddressView() (gas: 39411)
ZkCreate2Test:test_caseA_evmCreate2DoesNotReproduceAddress() (gas: 3860)
ZkCreate2Test:test_caseA_saltIsKeccakOfInitialOwner() (gas: 3274)
ZkCreate2Test:test_caseA_zkCreate2Address() (gas: 3622)
ZkCreate2Test:test_caseB_saltIsKeccakOfInitialOwner() (gas: 3288)
ZkCreate2Test:test_caseB_zkCreate2Address() (gas: 3616)
ZkCreate2Test:test_differentSaltDifferentAddress() (gas: 4151)
ZkCreate2Test:test_prefixIsKeccakOfZksyncCreate2() (gas: 3073)```

## Logged caller-frame measurements (from `forge test -vv`)

```
  gas: relayer->proxy recoverStrandedZkAccount (full balance, local): 119575
  gas: relayer->proxy recoverStrandedZkAccount (full balance, fork): 119496
```


_Note 2026-10-26: figures above were measured before the destination guard (`c.to != c.stranded && c.to != address(this)`) was added; the guard adds two calldata comparisons, a few tens of gas, and was not re-measured._
