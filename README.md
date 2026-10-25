# pegrecover — recovery of Binance-Peg BEP20 tokens stranded at ZK Stack smart-account addresses

A BEP draft and a tested reference implementation that let the administrator of the Binance-Peg BEP20
tokens on BNB Smart Chain return balances sent to addresses that only exist as ZKsync-CREATE2 smart
accounts (Abstract Global Wallet and similar) on ZK Stack chains. Nothing else can move those balances:
the addresses have no key, no EVM deployment can reach them, EIP-7702 needs the address's own key, and
no BSC fork has ever written code at a user address. The token proxy's storage is the only place the
balance exists, and its administrator is the only party that can change how it is read or written.

Worked case: BSC tx `0x512b66bef7392f9d1dd8fc3a9ee9234bd87dfdb7b0cd5c0395010f6576491f20`, 19,998
Binance-Peg USDC at `0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`, unmoved since 2026-02-11.

## Layout

| path | what |
| --- | --- |
| `FACTS.md` | every on-chain number used anywhere in this repo, with how it was read |
| `bep/BEP-XXX-zk-stranded-token-recovery.md` | the BEP draft, in the `bnb-chain/BEPs` format (BEP-1) |
| `bep/PROOF-PACK-0x6ae0.md` | case file for the worked example, for Binance support/engineering and the holder |
| `bep/PR-DESCRIPTION.md` | PR body for `bnb-chain/BEPs` |
| `contracts/` | Foundry project: `BEP20TokenImplementationV2` + `ZkCreate2` library, 70 tests (46 implementation + 24 review PoCs) incl. BSC mainnet fork upgrade tests; `README.md`, `GAS.md`, `REVIEW.md` |
| `research/ZK_ACCOUNT_SCHEMES.md` | which ZK Stack account factories bind the owner into the salt |

## How the recovery works

1. The token owner registers a ZK Stack account factory with its owner-binding scheme and pins the
   factory's account bytecode hash and constructor-input hash.
2. A claimant submits the factory's deployment tuple for the stranded address, a `RecoveryClaim`
   (stranded, to, amount, nonce, deadline) and an EIP-712 signature.
3. The token contract recomputes the ZKsync CREATE2 address from the tuple, checks the pins, checks the
   stranded address has no code on BSC, recovers the signer and requires `salt == keccak256(signer)`,
   then moves the balance with the existing internal transfer. No external calls, no off-chain approval.

Because the pins fix every input but the salt, and the salt is the hash of the signer, a key can only
ever claim the one address it would own under that factory.

## Build and test

```
cd contracts
forge build
forge test            # 70 tests; the 12 fork tests need the `bsc` RPC alias in foundry.toml (archive node)
```

Last full run: 2026-10-26 on srv1w, forge 1.8.3, `70 tests passed, 0 failed`, fork block 129782171.
See `contracts/README.md` for the verbatim transcript, storage-layout diff and the upgrade procedure.

## Status

Draft. Not submitted. Target: pull request to `bnb-chain/BEPs` (the token source repo
`bnb-chain/canonical-upgradeable-bep20` is archived and read-only).

By KURWA claude
