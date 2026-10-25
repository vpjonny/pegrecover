# Measured facts (on-chain, 2026-10-25). Use ONLY these numbers. Anything else must be labelled "unmeasured".

## The stranded case
- BSC tx 0x512b66bef7392f9d1dd8fc3a9ee9234bd87dfdb7b0cd5c0395010f6576491f20, block 80681471, 2026-02-11 23:25:06 UTC
- From: Binance hot wallet 0xe2fc31f816a9b94326492132018c3aecc4a93ae1
- Token: Binance-Peg USDC 0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d (18 decimals), amount 19,998.0, still there
- To: 0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86 — BSC: code 0 bytes, nonce 0, 0.0014 BNB. Abstract (chain 2741): code 1632 bytes, nonce 11620 (active AGW)
- Binance-Peg USDC is EIP-1967 proxy: impl 0xba5fe23f8a3a24bed3236f05f2fcf35fd0bf0b5c (5066 bytes), admin 0xd2f93484f2d319194cba95c5171b18c1d8cfd6c4 (EOA, nonce 175), getOwner() 0xf68a4b64162906eff0ff6ae34e2bb1cd42fef62d
- Impl selectors: standard BEP20 + mint(uint256) 0xa0712d68, burn(uint256), transferOwnership, renounceOwnership, getOwner. No blacklist / recovery / permit / pause.
- Source of impl: github.com/bnb-chain/canonical-upgradeable-bep20 (ARCHIVED 2022-09-14, read-only) contracts/BEP20TokenImplementation.sol

## AGW deployment math (Abstract, ZK Stack / EraVM)
- Factory (AccountFactory) 0x9b947df68d35281c972511b3e7bc875926f26c1a; deployAccount(bytes32 salt, bytes initializer) selector 0x574caef3
- salt = keccak256(abi.encodePacked(initialOwnerEOA))   (verified: keccak(0x07c65fe9...) == salt below)
- bytecodeHash (ZKsync format) 0x0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc
- constructorInput = abi.encode(address impl) with impl 0xaa3633b417483f932969edaef7cc4f1068f6faa9
- initializer selector 0xb4e581f5 = initialize(address k1Owner, address k1Validator, bytes[] modules, Call initCall); validator 0x74b9ae28ec45e3fa11533c7954752597c3de3e7a
- ZKsync CREATE2: address = keccak256( keccak256("zksyncCreate2") ++ bytes32(uint160(factory)) ++ salt ++ bytecodeHash ++ keccak256(constructorInput) )[12:]
- Case A: owner 0x07c65fe9f29a86b937604fa8d20a3fae19d7be48, salt 0x9c40f26d0e218dc6219fe7bae7b50af65cd87a6e1da558c4fa7bdaa33fad5185 -> 0x6ae0145e60b073e8c47b922f16c0f9e71e3efa86 (MATCH). Creation tx on Abstract 0xcdb63bfcbb7eab1f404dc9de6b79e787048f38307b1abce9fa5557405d7d5b9f, block 101456, tx.from 0x520cd27ab3b96141dc2b70dcd29f4fe2412e4bca
- Case B (jojo's own AGW, test ground): owner 0x349e6c340625a76f9c7ef76ed826e66cbd5bd7b4, salt 0x83110841e6184847ecdb526795e56824ed672100843d4bbb7e5365aa7ea81e10 -> 0xDb85b9035a02E0cB60bDd33655612930Ab414838 (MATCH). Creation tx 0x61214b7bd7184b0de73d2f9c9b506eafdf295c92c78970d776b4c131f5980367 block 89579
- EVM CREATE2 keccak(0xff ++ factory ++ salt ++ bytecodeHash-as-initcodehash) with case A inputs -> 0xbe2b2ffe38b18b1094c1cc24126ac140530f8d4f (so no EVM deployment reproduces the address)
- Factory/impl/validator were themselves deployed via ZKsync system Create2Factory 0x0000000000000000000000000000000000010000, salt 0 (factory bytecodeHash 0x010001b5d7006960c2...). Same three contracts exist byte-identical on zkSync Era (chain 324) at the same addresses; simulating the case-A deployAccount calldata on Era returns 0x6ae0145e... Sophon (50104), Lens (232), Cronos zkEVM (388), zkLink Nova (810180) run the ZK deployer (code at 0x8006) but lack the factory.
- AGW SDK (github.com/Abstract-Foundation/agw-sdk) VALID_CHAINS = {abstract 2741, abstractTestnet 11124, zksync 324, zksyncSepolia 300}; txs are ZKsync EIP-712 type 0x71. wallet_switchEthereumChain to other chains throws "Chain N not supported".
- Ownership caveat: AGW k1 owner can be changed after deployment; the salt binds only the INITIAL owner. The initial owner of case A is 0x07c65fe9...; current owner on Abstract not read (unmeasured).

## Context
- Abstract (Igloo Inc / Pudgy Penguins) shuts down 2026-12-15 (announced 2026-10-07). Abstract FAQ: "Do NOT send funds to your Abstract Global Wallet on any other network. Your AGW only exists on Abstract." and "it does not have a private key for you to export".
- Abstract feedback board (feedback.abs.xyz) has many identical losses on Arbitrum/Base/Polygon since Jan 2025; relayed Abstract stance: non-ZK-Stack chains unrecoverable, ZK Stack chains "may be recoverable in the future".
- Bounty post: x.com/eth_apple/status/2114351107086647600 (2026-10-25 13:39 UTC), $15,000 for recovery.
- BC Fusion precedent: TokenRecoverPortal system contract (0x...3000) releases Beacon-Chain assets on BSC against a Merkle proof + signature; BSC hard forks write code only to reserved system addresses (0x1000-0x3000 range). No BSC fork has ever written code to a user address.
- BNB Chain on-chain governance exists (Governor/Timelock system contracts) for parameter/system-contract changes.
