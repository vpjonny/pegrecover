// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {RecoveryBase, IV2, ITransparentUpgradeableProxy, Facts} from "./RecoveryBase.sol";

/// @notice Local proxy + V1 -> V2 upgrade, then every recovery rule.
contract RecoveryUnitTest is RecoveryBase {
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal tokenOwner = makeAddr("tokenOwner");
    address internal relayer = makeAddr("relayer");
    address internal beneficiary = makeAddr("beneficiary");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 internal constant STRANDED_AMOUNT = 1_000e18;

    address internal v1;
    address internal v2;
    IV2 internal token; // the proxy

    address internal freshOwner;
    uint256 internal freshPk;
    address internal stranded;
    bytes32 internal strandedSalt;

    function setUp() public {
        v1 = deployCode(V1_ARTIFACT);
        bytes memory init = abi.encodeWithSelector(
            IV2.initialize.selector, "Test Peg USD", "TPUSD", uint8(18), INITIAL_SUPPLY, true, tokenOwner
        );
        address proxy = deployCode(PROXY_ARTIFACT, abi.encode(v1, proxyAdmin, init));
        token = IV2(proxy);

        v2 = deployV2();
        vm.prank(proxyAdmin);
        ITransparentUpgradeableProxy(proxy).upgradeTo(v2);

        registerAgw(token, tokenOwner);

        (freshOwner, freshPk) = makeAddrAndKey("fresh initial owner");
        (stranded, strandedSalt) = agwAddressFor(freshOwner);

        vm.prank(tokenOwner);
        token.transfer(stranded, STRANDED_AMOUNT);
    }

    function _claim(uint256 amount, uint256 nonce) internal view returns (IV2.RecoveryClaim memory) {
        return IV2.RecoveryClaim({
            stranded: stranded, to: beneficiary, amount: amount, nonce: nonce, deadline: block.timestamp + 1 days
        });
    }

    // ------------------------------------------------------------ upgrade sanity

    function test_upgradePreservedV1State() public view {
        assertEq(token.name(), "Test Peg USD");
        assertEq(token.symbol(), "TPUSD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.getOwner(), tokenOwner);
        assertTrue(token.mintable());
        assertEq(token.balanceOf(tokenOwner), INITIAL_SUPPLY - STRANDED_AMOUNT);
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT);
        assertEq(address(uint160(uint256(vm.load(address(token), Facts.EIP1967_IMPL_SLOT)))), v2);
        assertAgwRegistered(token);
        assertEq(token.recoveryNonce(stranded), 0);
    }

    function test_pinnedConstructorInputHashIsKeccakOfEncodedImpl() public pure {
        assertEq(keccak256(abi.encode(Facts.AGW_IMPL)), Facts.AGW_CONSTRUCTOR_INPUT_HASH);
        assertEq(keccak256(Facts.agwConstructorInput()), Facts.AGW_CONSTRUCTOR_INPUT_HASH);
        // the prefix the BEP writer measured
        assertEq(bytes4(Facts.AGW_CONSTRUCTOR_INPUT_HASH), bytes4(0x7dc432c8));
    }

    function test_domainAndDigestMatchEip712() public view {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        assertEq(token.recoveryClaimDigest(c), claimDigest(token, c));
        assertEq(token.RECOVERY_CLAIM_TYPEHASH(), RECOVERY_CLAIM_TYPEHASH);
        bytes32 domain = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256(bytes("Test Peg USD")), keccak256(bytes("1")), block.chainid, address(token)
            )
        );
        assertEq(token.DOMAIN_SEPARATOR(), domain);
    }

    function test_zkCreate2AddressView() public view {
        assertEq(token.zkCreate2Address(agwDeployment(strandedSalt)), stranded);
        assertEq(token.zkCreate2Address(agwDeployment(Facts.CASE_A_SALT)), Facts.CASE_A_ADDR);
    }

    // --------------------------------------------------------------- happy paths

    function test_recover_fullBalance_amountZero() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);

        vm.expectEmit(true, true, true, true, address(token));
        emit IV2.Transfer(stranded, beneficiary, STRANDED_AMOUNT);
        vm.expectEmit(true, true, true, true, address(token));
        emit IV2.StrandedZkAccountRecovered(stranded, freshOwner, beneficiary, STRANDED_AMOUNT, Facts.AGW_FACTORY);

        vm.prank(relayer); // anyone may submit
        uint256 g = gasleft();
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        g -= gasleft();
        emit log_named_uint("gas: relayer->proxy recoverStrandedZkAccount (full balance, local)", g);

        assertEq(token.balanceOf(stranded), 0);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
        assertEq(token.totalSupply(), INITIAL_SUPPLY, "supply unchanged");
        assertEq(token.recoveryNonce(stranded), 1);
    }

    function test_recover_partialAmount_thenRest() public {
        uint256 part = 250e18;
        IV2.RecoveryClaim memory c = _claim(part, 0);
        vm.prank(relayer);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, signClaim(token, c, freshPk));
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT - part);
        assertEq(token.balanceOf(beneficiary), part);
        assertEq(token.recoveryNonce(stranded), 1);

        IV2.RecoveryClaim memory c2 = _claim(0, 1);
        vm.prank(relayer);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c2, signClaim(token, c2, freshPk));
        assertEq(token.balanceOf(stranded), 0);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
        assertEq(token.recoveryNonce(stranded), 2);
    }

    // ------------------------------------------------------------------ rejects

    function test_revert_wrongSigner() public {
        (, uint256 otherPk) = makeAddrAndKey("someone else");
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, otherPk);
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT);
    }

    function test_revert_unregisteredFactory() public {
        IV2.ZkDeployment memory d = agwDeployment(strandedSalt);
        d.factory = makeAddr("unknown factory");
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: factory not registered"));
        token.recoverStrandedZkAccount(d, c, sig);
    }

    function test_revert_schemeClearedToNone() public {
        vm.expectEmit(true, false, false, true, address(token));
        emit IV2.ZkFactorySchemeSet(Facts.AGW_FACTORY, IV2.OwnerScheme.NONE, bytes32(0), bytes32(0));
        vm.prank(tokenOwner);
        token.setZkFactoryScheme(Facts.AGW_FACTORY, IV2.OwnerScheme.NONE, Facts.AGW_BYTECODE_HASH, Facts.AGW_CONSTRUCTOR_INPUT_HASH);
        (IV2.OwnerScheme sch, bytes32 bh, bytes32 cih) = token.zkFactoryScheme(Facts.AGW_FACTORY);
        assertEq(uint8(sch), uint8(IV2.OwnerScheme.NONE));
        assertEq(bh, bytes32(0));
        assertEq(cih, bytes32(0));
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: factory not registered"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_wrongBytecodeHash() public {
        IV2.ZkDeployment memory d = agwDeployment(strandedSalt);
        d.bytecodeHash = keccak256("some other account bytecode");
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: bytecode hash not pinned for factory"));
        token.recoverStrandedZkAccount(d, c, sig);
    }

    function test_revert_wrongConstructorInput() public {
        IV2.ZkDeployment memory d = agwDeployment(strandedSalt);
        d.constructorInput = abi.encode(makeAddr("other impl"));
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: constructor input not pinned for factory"));
        token.recoverStrandedZkAccount(d, c, sig);
    }

    function test_revert_pinnedInputsCannotRetargetAnotherDerivedAddress() public {
        // A claimant who controls key K can only ever reach zkCreate2(factory, keccak(K), pinnedHash, pinnedInput).
        // Try to aim K's signature at a different AGW-style address by varying the constructor input.
        (address victimOwner,) = makeAddrAndKey("victim initial owner");
        (address victim,) = agwAddressFor(victimOwner);
        vm.prank(tokenOwner);
        token.transfer(victim, 10e18);
        IV2.RecoveryClaim memory c = _claim(0, 0);
        c.stranded = victim;
        bytes memory sig = signClaim(token, c, freshPk);
        IV2.ZkDeployment memory d = agwDeployment(strandedSalt);
        d.constructorInput = abi.encode(victimOwner); // arbitrary unpinned input
        vm.expectRevert(bytes("V2: constructor input not pinned for factory"));
        token.recoverStrandedZkAccount(d, c, sig);
        d = agwDeployment(strandedSalt); // pinned inputs: derivation lands on K's own address, not the victim
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(d, c, sig);
        assertEq(token.balanceOf(victim), 10e18);
    }

    function test_revert_derivationMismatch() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        IV2.ZkDeployment memory d = agwDeployment(keccak256(abi.encodePacked(makeAddr("someone else's salt"))));
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(d, c, sig);
    }

    function test_revert_claimedAddressNotDerived() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        c.stranded = tokenOwner; // try to drain a real holder
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_strandedAddressHasCode() public {
        vm.etch(stranded, hex"00");
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: stranded address has code"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_replay() public {
        IV2.RecoveryClaim memory c = _claim(400e18, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        vm.expectRevert(bytes("V2: bad nonce"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), 400e18);
    }

    function test_revert_wrongNonce() public {
        IV2.RecoveryClaim memory c = _claim(0, 1);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: bad nonce"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_expired() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.warp(c.deadline + 1);
        vm.expectRevert(bytes("V2: claim expired"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_deadlineInclusive() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.warp(c.deadline);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
    }

    function test_revert_amountExceedsBalance() public {
        IV2.RecoveryClaim memory c = _claim(STRANDED_AMOUNT + 1, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("BEP20: transfer amount exceeds balance"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_malleableSignature() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(freshPk, claimDigest(token, c));
        // flip to the high-s twin (same key, same message)
        bytes32 s2 = bytes32(SECP256K1_N - uint256(s));
        uint8 vFlip = v == 27 ? 28 : 27;
        bytes memory sig = abi.encodePacked(r, s2, vFlip);
        vm.expectRevert(bytes("V2: bad signature s"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_badSignatureLength() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        vm.expectRevert(bytes("V2: bad signature length"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, hex"deadbeef");
    }

    function test_revert_badV() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        (, bytes32 r, bytes32 s) = vm.sign(freshPk, claimDigest(token, c));
        vm.expectRevert(bytes("V2: bad signature v"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, abi.encodePacked(r, s, uint8(29)));
    }

    function test_revert_zeroSigner() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        // r = 0 makes ecrecover return address(0)
        bytes memory sig = abi.encodePacked(bytes32(0), bytes32(uint256(1)), uint8(27));
        vm.expectRevert(bytes("V2: zero signer"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_signatureBoundToClaimFields() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        c.to = relayer; // relayer tries to redirect the payout
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_revert_emptyStrandedBalance() public {
        (address emptyOwner, uint256 emptyPk) = makeAddrAndKey("owner with nothing stranded");
        (address emptyStranded, bytes32 emptySalt) = agwAddressFor(emptyOwner);
        IV2.RecoveryClaim memory c = IV2.RecoveryClaim({
            stranded: emptyStranded, to: beneficiary, amount: 0, nonce: 0, deadline: block.timestamp + 1
        });
        bytes memory sig = signClaim(token, c, emptyPk);
        vm.expectRevert(bytes("V2: nothing to recover"));
        token.recoverStrandedZkAccount(agwDeployment(emptySalt), c, sig);
    }

    // --------------------------------------------------------------- onlyOwner

    function test_revert_setZkFactorySchemeNotOwner() public {
        vm.prank(relayer);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        token.setZkFactoryScheme(Facts.AGW_FACTORY, IV2.OwnerScheme.NONE, bytes32(0), bytes32(0));
    }

    function test_revert_setZkFactorySchemeByProxyAdmin() public {
        // OZ 3.2 TransparentUpgradeableProxy: the proxy admin cannot reach the implementation
        vm.prank(proxyAdmin);
        vm.expectRevert(bytes("TransparentUpgradeableProxy: admin cannot fallback to proxy target"));
        token.setZkFactoryScheme(Facts.AGW_FACTORY, IV2.OwnerScheme.NONE, bytes32(0), bytes32(0));
    }

    function test_revert_setZkFactorySchemeZeroBytecodeHash() public {
        vm.prank(tokenOwner);
        vm.expectRevert(bytes("V2: zero bytecode hash"));
        token.setZkFactoryScheme(makeAddr("f"), IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, bytes32(0), Facts.AGW_CONSTRUCTOR_INPUT_HASH);
    }

    function test_setZkFactorySchemeEmits() public {
        address f = makeAddr("another factory");
        bytes32 bh = keccak256("bytecode");
        bytes32 cih = keccak256("ctor input");
        vm.expectEmit(true, false, false, true, address(token));
        emit IV2.ZkFactorySchemeSet(f, IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, bh, cih);
        vm.prank(tokenOwner);
        token.setZkFactoryScheme(f, IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, bh, cih);
        (IV2.OwnerScheme sch, bytes32 bh2, bytes32 cih2) = token.zkFactoryScheme(f);
        assertEq(uint8(sch), uint8(IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER));
        assertEq(bh2, bh);
        assertEq(cih2, cih);
    }
}
