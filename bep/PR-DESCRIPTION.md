## BEP-XXX: Recovery of Binance-Peg BEP20 tokens stranded at ZK Stack-derived smart-account addresses

New Standards BEP, status Draft. The number is a placeholder; per BEP-1 it takes this PR's number on merge, and the file should be renamed `BEPs/BEP-<number>.md` with the headings updated. Editors may judge that a token-implementation change belongs under `BAPs/`; the document is laid out so it can move there unchanged apart from the prefix.

### What it proposes

A Binance-Peg BEP20 balance sent on BSC to an Abstract Global Wallet address (or any ZKsync-CREATE2 smart account) cannot be moved by anyone: the address is a hash output under the ZK Stack formula (`keccak256("zksyncCreate2") ‖ …`), so it has no key, no EVM deployment can reach it (the EVM CREATE2 formula gives a different address for the same inputs), EIP-7702 needs the address's own signature, and no BSC fork has ever written code at a user address. The balance exists only in the token proxy's storage, which Binance administers.

The BEP specifies one append-only function for the Binance-Peg implementation, `recoverStrandedZkAccount`, that moves such a balance when the stranded address is code-less on BSC, equals the ZKsync-CREATE2 output of a factory the token owner has registered together with that factory's pinned account bytecode hash and constructor-input hash, the salt equals `keccak256(signer)`, and `signer` has signed an EIP-712 `RecoveryClaim(stranded, to, amount, nonce, deadline)`. With the pins, the salt is the only claim input not fixed by the registry, so a key can only ever claim the one address it would own under that factory. No off-chain approval, no hard fork, no system-contract change.

Worked case: BSC tx `0x512b66bef7392f9d1dd8fc3a9ee9234bd87dfdb7b0cd5c0395010f6576491f20`, 19,998 Binance-Peg USDC at `0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`, unmoved since 2026-02-11. Abstract shuts down 2026-12-15.

### Files

- `BEPs/BEP-XXX-zk-stranded-token-recovery.md` — the draft.
- Reference implementation and tests: `contracts/` in the companion repository (`pegrecover`), built on the vendored `bnb-chain/canonical-upgradeable-bep20` sources. URL to be added when published.
- Case file for the worked example: `PROOF-PACK-0x6ae0.md` in the companion repository.

### What to check

1. §5.2: the ZKsync CREATE2 formula and the two reproduced addresses (`0x6ae0…fa86`, `0xDb85…4838`); the EVM-CREATE2 control value `0xbe2b2ffe…8d4f`.
2. §5.3: EIP-712 domain (token `name()`, `"1"`, 56, proxy) and `RECOVERY_CLAIM_TYPEHASH` `0x835a1ddd…0057`.
3. §5.4–5.5: the checks, in particular that no path exists to move a balance from an address with code, from an unregistered factory, with a bytecode hash or constructor input other than the pinned ones, or without a signature whose signer hashes to the salt.
4. §7: storage layout is append-only relative to the deployed `BEP20TokenImplementation`.
5. §8: the owner-rotation limit (initial owner only) and the registry-governance note (the AGW factory's on-chain enforcement of `salt == keccak256(initialOwner)` was measured on zkSync Era: a mismatched salt reverts).
6. §10: the BC Fusion `TokenRecoverPortal` comparison is described as a claims portal, not as state surgery; correct it if the description is inaccurate.

All on-chain figures were read from public RPC on 2026-10-25/26; anything not read is labelled "unmeasured" in the text.

By KURWA claude
