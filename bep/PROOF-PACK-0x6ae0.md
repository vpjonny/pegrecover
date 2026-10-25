# Proof pack: 19,998 Binance-Peg USDC stranded at 0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86

Prepared 2026-10-26 for Binance support/engineering and for the account holder. Every number below was read from a public BSC RPC (`bsc-dataseed.bnbchain.org`, head block 129,781,795 on 2026-10-26) or from Abstract/zkSync Era public RPC on 2026-10-25, or was recomputed by hand from those reads. Nothing is estimated. Where a fact could not be read it is marked **unmeasured**.

## 1. In plain language

On 11 February 2026 Binance's hot wallet sent 19,998 USDC (the BSC "Binance-Peg" version) to the address `0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`. That address is an Abstract Global Wallet: a smart-contract wallet that exists on the Abstract chain, where it is in active use (its transaction counter stands at 11,620). The user copied the address out of the Abstract wallet and used it as a BSC withdrawal address.

On BSC the same address is empty. It has no code and has never sent a transaction. It is not an ordinary wallet address derived from a private key; it is the output of a hash formula used by Abstract (and other "ZK Stack" chains) when they create smart-contract wallets. That formula is different from the one BSC and every other EVM chain use. Running the same inputs through BSC's formula gives a different address, `0xbe2b2ffe38b18b1094c1cc24126ac140530f8d4f`. So nobody can ever create a contract at `0x6ae0…fa86` on BSC, nobody has a key for it, and the Abstract wallet software refuses to connect to BSC. The tokens are recorded in the USDC token contract under an address that can never act.

The USDC contract on BSC is an upgradeable contract administered by Binance. Its storage is the only place the balance exists, and the administrator is the only party that can change how that storage is read or written. No chain upgrade, no validator, no Abstract team action and no action by the user can move the balance. The companion BEP draft specifies a small, verifiable addition to the token contract that would let the user prove ownership with a signature from the wallet's original signing key (`0x07c65fe9f29a86b937604fa8d20a3fae19d7be48`) and move the balance.

Abstract has announced it will shut down on 2026-12-15. The address will still exist as a hash after that date, but the user's ability to demonstrate control of the Abstract-side wallet (e.g. by sending a transaction from it) ends with the chain.

## 2. The deposit

| Fact | Value |
| --- | --- |
| Chain | BNB Smart Chain, chainId 56 |
| Transaction | `0x512b66bef7392f9d1dd8fc3a9ee9234bd87dfdb7b0cd5c0395010f6576491f20` |
| Block | 80,681,471 (`0x4cf19ff`), block hash `0x72089642b500bb66fa78377cb07331fd67d082cd1faed85844a0a6eb51ad0e63` |
| Block timestamp | `0x698d0fd2` = 1,770,852,306 = 2026-02-11 23:25:06 UTC |
| Transaction index / log index | 16 / 76 |
| Type / status / gas used | legacy (`0x0`) / `0x1` success / 58,883 |
| From | `0xe2fc31f816a9b94326492132018c3aecc4a93ae1` (Binance hot wallet) |
| To (contract called) | `0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d` (Binance-Peg USDC) |
| Event | `Transfer(0xe2fc31f8…3ae1, 0x6ae0145e…fa86, 0x43c1800260e15b80000)` |
| Amount | `0x43c1800260e15b80000` = 19,998,000,000,000,000,000,000 base units = 19,998.0 USDC (18 decimals) |

## 3. The token contract

| Fact | Value | How read |
| --- | --- | --- |
| Proxy | `0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d` | — |
| `name()` | `"USD Coin"` | `eth_call` selector `0x06fdde03` |
| `symbol()` | `"USDC"` | `eth_call` selector `0x95d89b41` |
| `decimals()` | 18 | `eth_call` selector `0x313ce567` |
| `getOwner()` | `0xf68a4b64162906eff0ff6ae34e2bb1cd42fef62d` | `eth_call` selector `0x893d20e8` |
| EIP-1967 implementation slot `0x3608…2bbc` | `0xba5fe23f8a3a24bed3236f05f2fcf35fd0bf0b5c` | `eth_getStorageAt` |
| Implementation code size | 5,066 bytes | `eth_getCode` |
| EIP-1967 admin slot `0xb531…6103` | `0xd2f93484f2d319194cba95c5171b18c1d8cfd6c4` (EOA, nonce 175) | `eth_getStorageAt` |
| `balanceOf(0x6ae0…fa86)` at block 129,781,795 | `0x43c1800260e15b80000` = 19,998.0 | `eth_call` selector `0x70a08231` |
| Source | `github.com/bnb-chain/canonical-upgradeable-bep20`, `contracts/BEP20TokenImplementation.sol`; repository archived read-only 2022-09-14 | — |
| External functions | BEP20 standard, `mint(uint256)` (`0xa0712d68`, onlyOwner), `burn(uint256)`, `transferOwnership`, `renounceOwnership`, `getOwner`, `mintable` | source + selectors |
| Not present | blacklist, recovery, permit, pause | source |

The balance has not moved since the deposit: the same value is in storage 49,100,324 blocks later.

## 4. The stranded address on BSC

| Fact | Value | How read |
| --- | --- | --- |
| Code | none (`0x`) | `eth_getCode` |
| Nonce | 0 | `eth_getTransactionCount` |
| BNB balance | `0x4f94ae6af8000` = 1,400,000,000,000,000 wei = 0.0014 BNB | `eth_getBalance` |

No code, no outgoing transaction ever. The 0.0014 BNB is equally unreachable (origin of that BNB: **unmeasured**).

## 5. The same address on Abstract

| Fact | Value |
| --- | --- |
| Chain | Abstract, chainId 2741 (ZK Stack / EraVM) |
| Code | 1,632 bytes |
| Nonce | 11,620 |
| Creation transaction | `0xcdb63bfcbb7eab1f404dc9de6b79e787048f38307b1abce9fa5557405d7d5b9f`, block 101,456, `tx.from` `0x520cd27ab3b96141dc2b70dcd29f4fe2412e4bca` |
| Created by | `AccountFactory` `0x9b947df68d35281c972511b3e7bc875926f26c1a`, `deployAccount(bytes32 salt, bytes initializer)` selector `0x574caef3` |
| Account implementation (proxy target) | `0xaa3633b417483f932969edaef7cc4f1068f6faa9` |
| Initializer | selector `0xb4e581f5` = `initialize(address k1Owner, address k1Validator, bytes[] modules, Call initCall)` |
| k1Owner (initial) | `0x07c65fe9f29a86b937604fa8d20a3fae19d7be48` |
| k1Validator | `0x74b9ae28ec45e3fa11533c7954752597c3de3e7a` |
| Current k1 owner | **unmeasured** (can be rotated after deployment) |

Consistency check: the ZKsync bytecode hash below carries the code length in 32-byte words at bytes [2:4]: `0x0033` = 51 words = 1,632 bytes, which equals the code size read on Abstract.

## 6. The derivation, step by step

ZK Stack chains compute a CREATE2 address as

```
address = keccak256( keccak256("zksyncCreate2")
                   ‖ bytes32(uint160(factory))
                   ‖ salt
                   ‖ bytecodeHash
                   ‖ keccak256(constructorInput) )[12:32]
```

Inputs for this account:

| Input | Value |
| --- | --- |
| `keccak256("zksyncCreate2")` | `0x2020dba91b30cc0006188af794c2fb30dd8520db7e2c088b7fc7c103c00ca494` |
| `factory` (left-padded to 32 bytes) | `0x0000000000000000000000009b947df68d35281c972511b3e7bc875926f26c1a` |
| `salt` = `keccak256(0x07c65fe9f29a86b937604fa8d20a3fae19d7be48)` (20 raw bytes, no padding) | `0x9c40f26d0e218dc6219fe7bae7b50af65cd87a6e1da558c4fa7bdaa33fad5185` |
| `bytecodeHash` (ZKsync format) | `0x0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc` |
| `constructorInput` = `abi.encode(address 0xaa3633b4…faa9)` | `0x000000000000000000000000aa3633b417483f932969edaef7cc4f1068f6faa9` |
| `keccak256(constructorInput)` | `0x7dc432c80a70eef32157607a2f46e38cf1d957673706133ced678b80fcbf7ca2` |

Output: `keccak256(…)` low 20 bytes = **`0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`**. Match.

Control case (a second AGW, used to confirm the formula and the salt rule): owner `0x349e6c340625a76f9c7ef76ed826e66cbd5bd7b4` → salt `0x83110841e6184847ecdb526795e56824ed672100843d4bbb7e5365aa7ea81e10` → address `0xDb85b9035a02E0cB60bDd33655612930Ab414838`, created on Abstract in tx `0x61214b7bd7184b0de73d2f9c9b506eafdf295c92c78970d776b4c131f5980367`, block 89,579. Match.

Reproduce with any keccak256 implementation:

```python
from Crypto.Hash import keccak
def k(b): h = keccak.new(digest_bits=256); h.update(b); return h.digest()
factory = bytes.fromhex("9b947df68d35281c972511b3e7bc875926f26c1a")
owner   = bytes.fromhex("07c65fe9f29a86b937604fa8d20a3fae19d7be48")
bch     = bytes.fromhex("0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc")
cinput  = b"\x00"*12 + bytes.fromhex("aa3633b417483f932969edaef7cc4f1068f6faa9")
salt    = k(owner)
addr    = k(k(b"zksyncCreate2") + b"\x00"*12 + factory + salt + bch + k(cinput))[12:]
print(addr.hex())   # 6ae0145e60b073e8c47b922f16c0f9e71e3efa86
```

## 7. The EVM CREATE2 comparison

BSC (and every EVM chain) computes CREATE2 addresses as `keccak256(0xff ‖ deployer ‖ salt ‖ keccak256(initcode))[12:32]`. Feeding the same factory, salt and bytecode hash (as the init-code-hash slot) through that formula gives

```
keccak256(0xff ‖ 9b947df6…6c1a ‖ 9c40f26d…5185 ‖ 01000033…85bc)[12:] = 0xbe2b2ffe38b18b1094c1cc24126ac140530f8d4f
```

`0xbe2b2ffe…8d4f` has no code on BSC. No choice of EVM init code recovers `0x6ae0…fa86` either, because the prefix (`0xff` vs a 32-byte constant) and the layout of the hashed data differ; obtaining `0x6ae0…fa86` from any EVM CREATE2 would require finding a keccak256 preimage for a chosen 160-bit output. The factory `0x9b94…6c1a` itself has no code on BSC (`eth_getCode` returns `0x`), so a CREATE from it on BSC is impossible too; on Abstract the factory, the account implementation and the validator were deployed by the ZKsync system `Create2Factory` at `0x0000000000000000000000000000000000010000` with salt 0, an address that no EVM transaction can deploy to.

## 8. The zkSync Era simulation

The factory, the account implementation and the validator exist byte-identical at the same three addresses on zkSync Era (chainId 324). Simulating the creation calldata of §5 (`deployAccount` with the case's salt and initializer) against Era returns `0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`: the address is a property of the ZK Stack deployer and these inputs, not of Abstract specifically. Sophon (50104), Lens (232), Cronos zkEVM (388) and zkLink Nova (810180) run the ZK deployer (code at `0x…8006`) but do not have the factory, so the account cannot be created there without first deploying the factory at the same address.

This matters for the shutdown: on a ZK Stack chain the account can be recreated and controlled. On BSC it cannot, under any circumstances.

## 9. What the wallet software allows

The AGW SDK (`github.com/Abstract-Foundation/agw-sdk`) defines `VALID_CHAINS` = {abstract 2741, abstractTestnet 11124, zksync 324, zksyncSepolia 300}. Transactions are ZKsync EIP-712 type `0x71`, which BSC does not accept. `wallet_switchEthereumChain` to any other chain throws `Chain N not supported`. Abstract's FAQ: "Do NOT send funds to your Abstract Global Wallet on any other network. Your AGW only exists on Abstract." and the wallet "does not have a private key for you to export".

Whether the holder can export or use the k1 owner key `0x07c65fe9…be48` to sign an arbitrary EIP-712 message outside the AGW flow is **unmeasured**; the proposed recovery requires exactly that signature.

## 10. Why only the token administrator can move it

For a BEP20 balance to move, the token contract's `_transfer` must run with the holder as `msg.sender` (or after an `approve` from the holder). The four ways to be `msg.sender` on BSC, and why each is closed:

1. **Private key for `0x6ae0…fa86`.** None exists; the address is a hash output (§6), not a key derivative.
2. **Deploy code at `0x6ae0…fa86`.** CREATE needs the factory on BSC (absent) at a specific nonce; CREATE2 gives `0xbe2b2ffe…8d4f` (§7). Hitting `0x6ae0…fa86` needs a keccak256 preimage.
3. **EIP-7702 set-code (live on BSC as BEP-441).** The authorisation must be signed by the address's own key. See (1).
4. **Hard fork.** BSC forks have written code only to the system range `0x…1000`–`0x…3000`; none has written to a user address. Doing so per victim does not scale and is not how BSC has ever handled stranded assets (BC Fusion used a claims contract, BEP-299).

The balance is a storage slot in `0x8ac7…580d`. That contract is an EIP-1967 proxy whose admin (`0xd2f9…d6c4`) can change the implementation and whose owner (`0xf68a…f62d`) holds `mint` and ownership powers. The administrator can therefore add a function that moves the balance under a verifiable condition. Nobody else can.

## 11. What is asked

Adopt the V2 implementation in the companion BEP draft (`BEP-XXX-zk-stranded-token-recovery.md`): one function that moves a balance from a code-less BSC address if (a) the address is the ZKsync-CREATE2 output of a registered factory, (b) the salt is `keccak256(signer)`, and (c) `signer` signed an EIP-712 `RecoveryClaim` naming the destination and amount. For this case the inputs are the tuple in §6 and a signature from `0x07c65fe9f29a86b937604fa8d20a3fae19d7be48`. The verification is deterministic; the administrator's step is to upgrade the proxy and register the AGW factory `0x9b94…6c1a` under `SALT_IS_KECCAK_OF_INITIAL_OWNER`.

EIP-712 values for this token: domain `name = "USD Coin"`, `version = "1"`, `chainId = 56`, `verifyingContract = 0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d`; domain separator `0xfc877ab7304c7c158d3fd77b876e283f403d7f06af357978e51071ca51fe27b9`; `RECOVERY_CLAIM_TYPEHASH = 0x835a1ddd6f21721e0341455f19d4804951b583f81b1c0e0418cb09db6a4e0057`.

## 12. Context

- Abstract shutdown announced 2026-10-07, effective 2026-12-15.
- Abstract feedback board (feedback.abs.xyz): many identical losses on Arbitrum, Base and Polygon since January 2025; relayed Abstract stance: non-ZK-Stack chains unrecoverable, ZK Stack chains "may be recoverable in the future".
- Bounty for this recovery: x.com/eth_apple/status/2114351107086647600, 2026-10-25 13:39 UTC, $15,000.
- Number of other Binance-Peg balances stranded at ZK-derived addresses on BSC: **unmeasured**.

## 13. Factory enforcement (measured 2026-10-26)

On zkSync Era, where the same `AccountFactory` code is deployed at the same address, `eth_call` of `deployAccount` with the case's initializer and its original salt returns `0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86`; the same initializer with any other salt (`keccak256(0x11…11)`, `0x00…00`) reverts with custom error selector `0x8b3152e6`. The factory, not only the wallet software, binds the salt to the initial owner.

## 14. Unmeasured items

- Current k1 owner of the AGW on Abstract (only the initial owner `0x07c65fe9…be48` is proven by the address).
- Whether the holder can sign arbitrary EIP-712 messages with `0x07c65fe9…be48`.
- Origin of the 0.0014 BNB at `0x6ae0…fa86` on BSC. (Measured 2026-10-25: `0x07c65fe9…be48` holds 0.001 BNB on BSC, nonce 0, zero Binance-Peg USDC.)
- Total count and value of the loss class on BSC.
