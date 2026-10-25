# Gas — `recoverStrandedZkAccount`

Measured on srv1w with `forge 1.8.3` (solc 0.6.12 for the implementation, optimizer on, 200 runs),
2026-10-26, from the run whose transcript is in README.md. Nothing below is estimated.

## Headline numbers

| Measurement | Gas | How measured |
|---|---|---|
| Implementation frame, full-balance recovery, **BSC fork** (`test_fork_recoverFreshAgwAccount`) | **75,461** | `forge test --match-test test_fork_recoverFreshAgwAddress --gas-report`, row `recoverStrandedZkAccount` |
| Implementation frame, full-balance recovery, local proxy (`test_recover_fullBalance_amountZero`) | 75,461 | same, local test |
| Implementation frame, partial then remainder (`test_recover_partialAmount_thenRest`) | 73,434 (first, partial) / 41,278 (second, warm nonce + recipient) | same |
| Caller frame: relayer -> proxy -> V2, full balance, **BSC fork** | **114,751** | `gasleft()` delta around the external call inside the test (logged) |
| Caller frame: relayer -> proxy -> V2, full balance, local | 114,785 | same |
| Earliest revert (`factory not registered`) | 3,224 | `--gas-report` Min column over 23 calls |

Caller-frame figures include the TransparentUpgradeableProxy dispatch and the two external self-calls
(`this.name()` for the EIP-712 domain, `this.balanceOf()` for the `amount == 0` path). They exclude the
21,000 intrinsic transaction gas and calldata gas, so a real transaction costs more than 114,751; that
total was not measured. BNB cost at a given gas price was not measured.

## Raw `forge test --gas-report` (all 39 tests)

```
╭------------------------------------------------------------------------+-----------------+-------+--------+-------+---------╮
| src/BEP20TokenImplementationV2.sol:BEP20TokenImplementationV2 Contract |                 |       |        |       |         |
+=============================================================================================================================+
| Deployment Cost                                                        | Deployment Size |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                1970671 |            8907 |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
|                                                                        |                 |       |        |       |         |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| Function Name                                                          | Min             | Avg   | Median | Max   | # Calls |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| DOMAIN_SEPARATOR                                                       |            7959 |  7959 |   7959 |  7959 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| RECOVERY_CLAIM_TYPEHASH                                                |             295 |   295 |    295 |   295 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| balanceOf                                                              |            2598 |  2598 |   2598 |  2598 |      26 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| decimals                                                               |            2392 |  2392 |   2392 |  2392 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| getOwner                                                               |            2470 |  2470 |   2470 |  2470 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| mintable                                                               |            2468 |  2468 |   2468 |  2468 |       1 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| name                                                                   |            2982 |  2982 |   2982 |  2982 |      42 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoverStrandedZkAccount                                               |            3224 | 35779 |  40160 | 75461 |      23 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoveryClaimDigest                                                    |            9085 |  9085 |   9085 |  9085 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| recoveryNonce                                                          |            2664 |  2664 |   2664 |  2664 |       6 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| setZkFactoryScheme                                                     |            2733 | 24335 |  26415 | 26415 |      31 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| symbol                                                                 |            3069 |  3069 |   3069 |  3069 |       2 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| totalSupply                                                            |            2440 |  2440 |   2440 |  2440 |       5 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| transfer                                                               |           30168 | 30168 |  30168 | 30168 |      26 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| zkCreate2Address                                                       |            1523 |  1523 |   1523 |  1523 |       4 |
|------------------------------------------------------------------------+-----------------+-------+--------+-------+---------|
| zkFactoryScheme                                                        |            2675 |  2675 |   2675 |  2675 |       3 |
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
| initialize                                                                |          137536 | 137536 | 137536 | 137536 |      25 |
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
| fallback                                                            |            3341 | 34967 |  36999 | 108626 |     142 |
|---------------------------------------------------------------------+-----------------+-------+--------+--------+---------|
| upgradeTo                                                           |           32691 | 32691 |  32691 |  32691 |      25 |
╰---------------------------------------------------------------------+-----------------+-------+--------+--------+---------╯
```

## Per-test gas snapshot (`forge snapshot`)

```
ForkTest:test_fork_caseA_claimPassesEveryCheckExceptSignature() (gas: 2083503)
ForkTest:test_fork_caseA_isStrandedAtForkBlock() (gas: 37866)
ForkTest:test_fork_caseA_randomKeyRejected() (gas: 2220472)
ForkTest:test_fork_recoverFreshAgwAddress() (gas: 2506044)
ForkTest:test_fork_registerSchemeOnlyByTokenOwner() (gas: 2084254)
ForkTest:test_fork_upgradeOnlyByProxyAdmin() (gas: 2044627)
ForkTest:test_fork_upgradePreservesStorage() (gas: 2315524)
RecoveryUnitTest:test_deadlineInclusive() (gas: 154534)
RecoveryUnitTest:test_domainAndDigestMatchEip712() (gas: 82256)
RecoveryUnitTest:test_recover_fullBalance_amountZero() (gas: 227023)
RecoveryUnitTest:test_recover_partialAmount_thenRest() (gas: 363837)
RecoveryUnitTest:test_revert_amountExceedsBalance() (gas: 112529)
RecoveryUnitTest:test_revert_badSignatureLength() (gas: 84387)
RecoveryUnitTest:test_revert_badV() (gas: 105508)
RecoveryUnitTest:test_revert_claimedAddressNotDerived() (gas: 75310)
RecoveryUnitTest:test_revert_derivationMismatch() (gas: 74755)
RecoveryUnitTest:test_revert_emptyStrandedBalance() (gas: 111311)
RecoveryUnitTest:test_revert_expired() (gas: 76590)
RecoveryUnitTest:test_revert_malleableSignature() (gas: 105515)
RecoveryUnitTest:test_revert_replay() (gas: 202177)
RecoveryUnitTest:test_revert_schemeClearedToNone() (gas: 110959)
RecoveryUnitTest:test_revert_setZkFactorySchemeByProxyAdmin() (gas: 35077)
RecoveryUnitTest:test_revert_setZkFactorySchemeNotOwner() (gas: 42527)
RecoveryUnitTest:test_revert_signatureBoundToClaimFields() (gas: 111361)
RecoveryUnitTest:test_revert_strandedAddressHasCode() (gas: 79024)
RecoveryUnitTest:test_revert_unregisteredFactory() (gas: 75966)
RecoveryUnitTest:test_revert_wrongNonce() (gas: 78524)
RecoveryUnitTest:test_revert_wrongSigner() (gas: 126356)
RecoveryUnitTest:test_revert_zeroSigner() (gas: 88936)
RecoveryUnitTest:test_setZkFactorySchemeEmits() (gas: 82648)
RecoveryUnitTest:test_upgradePreservedV1State() (gas: 188807)
RecoveryUnitTest:test_zkCreate2AddressView() (gas: 39387)
ZkCreate2Test:test_caseA_evmCreate2DoesNotReproduceAddress() (gas: 3860)
ZkCreate2Test:test_caseA_saltIsKeccakOfInitialOwner() (gas: 3274)
ZkCreate2Test:test_caseA_zkCreate2Address() (gas: 3622)
ZkCreate2Test:test_caseB_saltIsKeccakOfInitialOwner() (gas: 3288)
ZkCreate2Test:test_caseB_zkCreate2Address() (gas: 3616)
ZkCreate2Test:test_differentSaltDifferentAddress() (gas: 4151)
ZkCreate2Test:test_prefixIsKeccakOfZksyncCreate2() (gas: 3073)```

## Logged caller-frame measurements (from `forge test -vv`)

```
  gas: relayer->proxy recoverStrandedZkAccount (full balance, local): 114785
  gas: relayer->proxy recoverStrandedZkAccount (full balance, fork): 114751
```
