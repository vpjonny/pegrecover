// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {RecoveryBase, IV2, ITransparentUpgradeableProxy, Facts} from "./RecoveryBase.sol";

/// @notice Adversarial review PoCs (see REVIEW.md). Every test here PASSES; a passing test
///         demonstrates either that an attack is blocked or that a documented behaviour holds.
///         None of these modify src/.
contract ReviewUnitTest is RecoveryBase {
    address internal proxyAdmin = makeAddr("proxyAdmin");
    address internal tokenOwner = makeAddr("tokenOwner");
    address internal relayer = makeAddr("relayer");
    address internal attacker = makeAddr("attacker");
    address internal beneficiary = makeAddr("beneficiary");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 internal constant STRANDED_AMOUNT = 1_000e18;

    address internal v1;
    address internal v2;
    IV2 internal token;
    address internal proxy;

    address internal freshOwner;
    uint256 internal freshPk;
    address internal stranded;
    bytes32 internal strandedSalt;

    function setUp() public {
        v1 = deployCode(V1_ARTIFACT);
        bytes memory init = abi.encodeWithSelector(
            IV2.initialize.selector, "Test Peg USD", "TPUSD", uint8(18), INITIAL_SUPPLY, true, tokenOwner
        );
        proxy = deployCode(PROXY_ARTIFACT, abi.encode(v1, proxyAdmin, init));
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

    // ------------------------------------------------------------ 1. storage layout

    /// Raw slot proof of the layout: slot 0 Initializable flags, 1 _balances, 2 _allowances, 3 _totalSupply,
    /// 6 packed decimals|owner|mintable, 7 _zkFactoryScheme, 8 _recoveryNonce. Read through the proxy so
    /// this is the layout V2 actually sees via delegatecall.
    function test_review_rawStorageSlots() public {
        // slot 0: _initialized = true (offset 0), _initializing = false (offset 1)
        assertEq(vm.load(proxy, bytes32(uint256(0))), bytes32(uint256(1)), "slot0 initialized flag");
        // slot 1: _balances[stranded]
        bytes32 balSlot = keccak256(abi.encode(stranded, uint256(1)));
        assertEq(uint256(vm.load(proxy, balSlot)), STRANDED_AMOUNT, "balance slot");
        // slot 2: _allowances[owner][spender]
        vm.prank(tokenOwner);
        token.transfer(beneficiary, 1); // touch nothing in slot 2 yet; set an allowance below
        vm.prank(tokenOwner);
        (bool ok,) = proxy.call(abi.encodeWithSignature("approve(address,uint256)", attacker, 777));
        assertTrue(ok);
        bytes32 allowSlot = keccak256(abi.encode(attacker, keccak256(abi.encode(tokenOwner, uint256(2)))));
        assertEq(uint256(vm.load(proxy, allowSlot)), 777, "allowance slot");
        // slot 3: _totalSupply
        assertEq(uint256(vm.load(proxy, bytes32(uint256(3)))), INITIAL_SUPPLY, "totalSupply slot");
        // slot 6: uint8 decimals | address owner | bool mintable, packed
        uint256 w = uint256(vm.load(proxy, bytes32(uint256(6))));
        assertEq(uint8(w), 18, "decimals @ offset 0");
        assertEq(address(uint160(w >> 8)), tokenOwner, "owner @ offset 1");
        assertEq(uint8(w >> 168), 1, "mintable @ offset 21");
        assertEq(w >> 176, 0, "no bytes above mintable");
        // slot 7: _zkFactoryScheme[AGW_FACTORY] = {scheme, bytecodeHash, constructorInputHash}
        bytes32 base = keccak256(abi.encode(Facts.AGW_FACTORY, uint256(7)));
        assertEq(uint256(vm.load(proxy, base)), 1, "scheme word");
        assertEq(vm.load(proxy, bytes32(uint256(base) + 1)), Facts.AGW_BYTECODE_HASH, "bytecodeHash word");
        assertEq(vm.load(proxy, bytes32(uint256(base) + 2)), Facts.AGW_CONSTRUCTOR_INPUT_HASH, "cih word");
        // slot 8: _recoveryNonce[stranded]
        bytes32 nonceSlot = keccak256(abi.encode(stranded, uint256(8)));
        assertEq(uint256(vm.load(proxy, nonceSlot)), 0);
        IV2.RecoveryClaim memory c = _claim(1e18, 0);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, signClaim(token, c, freshPk));
        assertEq(uint256(vm.load(proxy, nonceSlot)), 1, "nonce slot after claim");
        // the proxy's own state is in EIP-1967 hashed slots, not in 0..56
        assertEq(address(uint160(uint256(vm.load(proxy, Facts.EIP1967_IMPL_SLOT)))), v2);
        assertEq(address(uint160(uint256(vm.load(proxy, Facts.EIP1967_ADMIN_SLOT)))), proxyAdmin);
    }

    // ------------------------------------------------------------ 7. upgrade path

    /// initialize() must stay dead after the upgrade (slot 0 flag survives). If it did not, anyone could
    /// re-initialize, take ownership and mint. This is the single most important upgrade invariant.
    function test_review_initializeCannotRerunAfterUpgrade() public {
        vm.prank(attacker);
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        token.initialize("Evil", "EVIL", 18, 1e30, true, attacker);
        assertEq(token.getOwner(), tokenOwner);
    }

    /// No V2 selector equals a TransparentUpgradeableProxy admin selector.
    function test_review_noSelectorClashWithProxy() public pure {
        bytes4[5] memory proxySel = [
            ITransparentUpgradeableProxy.admin.selector,
            ITransparentUpgradeableProxy.implementation.selector,
            ITransparentUpgradeableProxy.changeAdmin.selector,
            ITransparentUpgradeableProxy.upgradeTo.selector,
            ITransparentUpgradeableProxy.upgradeToAndCall.selector
        ];
        bytes4[8] memory v2Sel = [
            IV2.recoverStrandedZkAccount.selector,
            IV2.setZkFactoryScheme.selector,
            IV2.zkFactoryScheme.selector,
            IV2.recoveryNonce.selector,
            IV2.zkCreate2Address.selector,
            IV2.DOMAIN_SEPARATOR.selector,
            IV2.recoveryClaimDigest.selector,
            IV2.RECOVERY_CLAIM_TYPEHASH.selector
        ];
        for (uint256 i = 0; i < v2Sel.length; i++) {
            for (uint256 j = 0; j < proxySel.length; j++) {
                assertTrue(v2Sel[i] != proxySel[j]);
            }
        }
    }

    /// The raw V2 implementation contract is un-initialized and anyone may initialize it. This is the
    /// same exposure V1 has; it does not touch the proxy's storage. Documented as Info.
    function test_review_rawImplementationInitializableByAnyone_noEffectOnProxy() public {
        vm.startPrank(attacker);
        IV2(v2).initialize("Raw", "RAW", 18, 1e18, true, attacker);
        assertEq(IV2(v2).getOwner(), attacker);
        IV2(v2).setZkFactoryScheme(makeAddr("evil factory"), IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, bytes32(uint256(1)), bytes32(0));
        vm.stopPrank();
        // proxy untouched
        assertEq(token.getOwner(), tokenOwner);
        (IV2.OwnerScheme sch,,) = token.zkFactoryScheme(makeAddr("evil factory"));
        assertEq(uint8(sch), uint8(IV2.OwnerScheme.NONE));
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    // ------------------------------------------------------------ 2. which addresses are reachable

    function test_review_zeroStrandedUnreachable() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        c.stranded = address(0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    function test_review_proxyItselfAndOwnerUnreachable() public {
        // give the proxy and the owner balances, then try to name them
        vm.prank(tokenOwner);
        token.transfer(proxy, 5e18);
        address[2] memory targets = [proxy, tokenOwner];
        for (uint256 i = 0; i < 2; i++) {
            IV2.RecoveryClaim memory c = _claim(0, 0);
            c.stranded = targets[i];
            bytes memory sig = signClaim(token, c, freshPk);
            vm.expectRevert(bytes("V2: derivation mismatch"));
            token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        }
        assertEq(token.balanceOf(proxy), 5e18);
    }

    /// EIP-7702 (BEP-441) delegation designator 0xef0100 ++ address is 23 bytes of code: claim is blocked.
    function test_review_eip7702DesignatorBlocksClaim() public {
        vm.etch(stranded, abi.encodePacked(hex"ef0100", attacker));
        assertEq(stranded.code.length, 23);
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: stranded address has code"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    /// Owner registers an arbitrary factory with arbitrary pins: still cannot name a funded address,
    /// because stranded must be the keccak output of (factory, keccak(signer), bh, cih).
    function test_review_ownerRegistryCannotTargetFundedAddress() public {
        address evilFactory = makeAddr("evil factory");
        vm.prank(tokenOwner);
        token.setZkFactoryScheme(evilFactory, IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, bytes32(uint256(0xdead)), keccak256(""));
        (address ownerKeyAddr, uint256 ownerKeyPk) = makeAddrAndKey("owner's claim key");
        IV2.ZkDeployment memory d = IV2.ZkDeployment({
            factory: evilFactory, salt: keccak256(abi.encodePacked(ownerKeyAddr)), bytecodeHash: bytes32(uint256(0xdead)), constructorInput: ""
        });
        // the only address this key can reach under the evil factory:
        address reachable = token.zkCreate2Address(d);
        assertEq(token.balanceOf(reachable), 0);
        // try the stranded victim address instead
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, ownerKeyPk);
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(d, c, sig);
        // and with the real AGW tuple but the owner's key: signer binding fails
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT);
    }

    /// Out-of-range enum in setZkFactoryScheme: the 0.6.12 ABI decoder rejects it. If it ever did not,
    /// recover would still revert with "unknown scheme".
    function test_review_enumOutOfRangeRejected() public {
        bytes memory data = abi.encodeWithSelector(
            IV2.setZkFactoryScheme.selector, makeAddr("f"), uint8(2), bytes32(uint256(1)), bytes32(0)
        );
        vm.prank(tokenOwner);
        (bool ok,) = proxy.call(data);
        assertFalse(ok, "enum 2 must be rejected by the decoder");
        (IV2.OwnerScheme sch,,) = token.zkFactoryScheme(makeAddr("f"));
        assertEq(uint8(sch), 0);
    }

    // ------------------------------------------------------------ 3. signature domain

    /// Two proxies with the same name() share nothing: verifyingContract differs.
    function test_review_noReplayAcrossProxiesWithSameName() public {
        bytes memory init = abi.encodeWithSelector(
            IV2.initialize.selector, "Test Peg USD", "TPUSD", uint8(18), INITIAL_SUPPLY, true, tokenOwner
        );
        address proxy2 = deployCode(PROXY_ARTIFACT, abi.encode(v2, proxyAdmin, init));
        IV2 token2 = IV2(proxy2);
        registerAgw(token2, tokenOwner);
        vm.prank(tokenOwner);
        token2.transfer(stranded, STRANDED_AMOUNT);
        assertEq(keccak256(bytes(token.name())), keccak256(bytes(token2.name())));
        assertTrue(token.DOMAIN_SEPARATOR() != token2.DOMAIN_SEPARATOR());

        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk); // signed for proxy 1
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token2.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token2.balanceOf(stranded), STRANDED_AMOUNT);
        // the same bytes still work where they were meant to
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
    }

    function test_review_noCrossChainReplay() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        bytes32 dom = token.DOMAIN_SEPARATOR();
        vm.chainId(1);
        assertTrue(token.DOMAIN_SEPARATOR() != dom, "domain tracks chainid at call time");
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
    }

    /// Dirty high bits in a calldata address field of the claim: either the decoder rejects the calldata
    /// or the cleaned value hashes to a digest the signer did not sign. No funds move either way.
    function test_review_dirtyCalldataAddressDoesNotMove() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        bytes memory data = abi.encodeCall(IV2.recoverStrandedZkAccount, (agwDeployment(strandedSalt), c, sig));
        // layout: 4 selector | word0 offset(d) | word1..5 c (static tuple inline) | word6 offset(sig) ...
        // c.to is word 2 -> bytes [4+64, 4+96). Set its 12 high bytes to 0xff.
        for (uint256 i = 0; i < 12; i++) data[4 + 64 + i] = 0xff;
        (bool ok,) = proxy.call(data);
        assertFalse(ok);
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT);
        assertEq(token.recoveryNonce(stranded), 0);
    }

    // ------------------------------------------------------------ 4. nonce / griefing

    function test_review_thirdPartyCannotBurnNonce() public {
        (, uint256 pk) = makeAddrAndKey("attacker key");
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory badSig = signClaim(token, c, pk);
        vm.prank(attacker);
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, badSig);
        assertEq(token.recoveryNonce(stranded), 0, "nonce untouched by failed claim");
        // victim's claim at nonce 0 still works
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, signClaim(token, c, freshPk));
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
    }

    function test_review_relayerFrontrunSameClaim_victimStillPaid() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.prank(attacker); // front-runner copies the calldata
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        vm.prank(relayer);
        vm.expectRevert(bytes("V2: bad nonce"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT, "destination fixed by the signature");
    }

    /// Griefing attempt: attacker tops up the stranded balance so an exact-amount claim no longer
    /// matches the balance. It still executes (amount <= balance), remainder stays claimable.
    function test_review_topUpDoesNotBlockExactAmountClaim() public {
        IV2.RecoveryClaim memory c = _claim(STRANDED_AMOUNT, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.prank(tokenOwner);
        token.transfer(stranded, 1);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
        assertEq(token.balanceOf(stranded), 1);
    }

    // ------------------------------------------------------------ 5. amount == 0 semantics

    /// A signed full-balance claim is a bearer sweep until its deadline: deposits that land after
    /// signing are moved too. Behaviour is per spec; flagged so signers set short deadlines.
    function test_review_fullBalanceClaimSweepsLaterDeposits() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.prank(tokenOwner);
        token.transfer(stranded, 5_000e18); // lands after the signature was produced
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT + 5_000e18);
        assertEq(token.balanceOf(stranded), 0);
    }

    /// to == stranded: consumes a nonce, emits Transfer(s, s, amt), moves nothing. Signer's own choice.
    function test_review_toEqualsStrandedRejected() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        c.to = stranded;
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: bad destination"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(stranded), STRANDED_AMOUNT);
        assertEq(token.recoveryNonce(stranded), 0);
    }

    /// to == the token proxy: rejected by the destination guard (would strand the balance again).
    function test_review_toEqualsProxyRejected() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        c.to = proxy;
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: bad destination"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(proxy), 0);
        // the proxy has code, so it can never be a recover() subject either
        IV2.RecoveryClaim memory c2 = _claim(0, 0);
        c2.stranded = proxy;
        bytes memory sig2 = signClaim(token, c2, freshPk);
        vm.expectRevert(bytes("V2: derivation mismatch"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c2, sig2);
    }

    /// totalSupply is invariant over any sequence of claims; Transfer event carries the executed amount
    /// (not the signed 0).
    function test_review_supplyInvariantAndEventAmount() public {
        uint256 s0 = token.totalSupply();
        IV2.RecoveryClaim memory c = _claim(0, 0);
        vm.expectEmit(true, true, true, true, proxy);
        emit IV2.Transfer(stranded, beneficiary, STRANDED_AMOUNT);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, signClaim(token, c, freshPk));
        assertEq(token.totalSupply(), s0);
    }

    // ------------------------------------------------------------ 6. owner powers

    /// Owner can disable a registered factory at any time, which cancels every outstanding signed claim
    /// for that factory (claims are not vested). Spec'd; documented as a governance dependency.
    function test_review_ownerCanCancelOutstandingClaimsByClearingRegistry() public {
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.prank(tokenOwner);
        token.setZkFactoryScheme(Facts.AGW_FACTORY, IV2.OwnerScheme.NONE, 0, 0);
        vm.expectRevert(bytes("V2: factory not registered"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        // re-register: the same signature is valid again (nonce was never consumed)
        registerAgw(token, tokenOwner);
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        assertEq(token.balanceOf(beneficiary), STRANDED_AMOUNT);
    }

    /// Owner re-pins a different bytecodeHash: existing claims fail at the pin check, nothing moves.
    function test_review_ownerRepinBreaksClaimsOnly() public {
        vm.prank(tokenOwner);
        token.setZkFactoryScheme(
            Facts.AGW_FACTORY, IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, keccak256("other"), Facts.AGW_CONSTRUCTOR_INPUT_HASH
        );
        IV2.RecoveryClaim memory c = _claim(0, 0);
        bytes memory sig = signClaim(token, c, freshPk);
        vm.expectRevert(bytes("V2: bytecode hash not pinned for factory"));
        token.recoverStrandedZkAccount(agwDeployment(strandedSalt), c, sig);
        // ordinary token functions unaffected
        vm.prank(tokenOwner);
        assertTrue(token.transfer(beneficiary, 1));
    }
}

/// @notice Fork PoCs on the real Binance-Peg USDC proxy.
contract ReviewForkTest is RecoveryBase {
    IV2 internal usdc = IV2(Facts.BSC_USDC);
    address internal attacker = makeAddr("attacker");

    /// §5.3 of the BEP states this value for Binance-Peg USDC.
    bytes32 internal constant SPEC_USDC_DOMAIN = 0xfc877ab7304c7c158d3fd77b876e283f403d7f06af357978e51071ca51fe27b9;

    function setUp() public {
        vm.createSelectFork("bsc", Facts.FORK_BLOCK);
    }

    function _upgrade() internal returns (address v2) {
        v2 = deployV2();
        vm.prank(Facts.BSC_USDC_PROXY_ADMIN);
        ITransparentUpgradeableProxy(Facts.BSC_USDC).upgradeTo(v2);
    }

    /// The deployed V1 was compiled with solc 0.6.4 (metadata), the vendored copy with 0.6.12. Prove the
    /// slots V2 depends on hold the expected values on the live proxy before and after the upgrade, and
    /// that initialize() stays dead. Also checks mintable() and an allowance, which Fork.t.sol does not.
    function test_reviewFork_slot0MintableAllowanceSurviveUpgrade_initializeDead() public {
        assertEq(vm.load(Facts.BSC_USDC, bytes32(uint256(0))), bytes32(uint256(1)), "live slot0 = initialized");
        uint256 w = uint256(vm.load(Facts.BSC_USDC, bytes32(uint256(6))));
        assertEq(uint8(w), 18);
        assertEq(address(uint160(w >> 8)), Facts.BSC_USDC_OWNER);
        assertEq(uint8(w >> 168), 1, "live mintable bit");
        assertTrue(usdc.mintable());

        vm.prank(Facts.BINANCE_HOT_WALLET);
        (bool ok,) = Facts.BSC_USDC.call(abi.encodeWithSignature("approve(address,uint256)", attacker, 12345));
        assertTrue(ok);

        _upgrade();

        assertEq(vm.load(Facts.BSC_USDC, bytes32(uint256(0))), bytes32(uint256(1)));
        assertTrue(usdc.mintable());
        (, bytes memory ret) = Facts.BSC_USDC.staticcall(
            abi.encodeWithSignature("allowance(address,address)", Facts.BINANCE_HOT_WALLET, attacker)
        );
        assertEq(abi.decode(ret, (uint256)), 12345, "allowance survives");

        vm.prank(attacker);
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        usdc.initialize("Evil", "EVIL", 18, 1e30, true, attacker);
        assertEq(usdc.getOwner(), Facts.BSC_USDC_OWNER);
    }

    function test_reviewFork_domainSeparatorMatchesSpec() public {
        _upgrade();
        assertEq(usdc.DOMAIN_SEPARATOR(), SPEC_USDC_DOMAIN);
    }

    /// Owner's mint power is unchanged by the upgrade (the registry adds nothing to it).
    function test_reviewFork_ownerMintUnchanged() public {
        _upgrade();
        uint256 s0 = usdc.totalSupply();
        vm.prank(Facts.BSC_USDC_OWNER);
        assertTrue(usdc.mint(1e18));
        assertEq(usdc.totalSupply(), s0 + 1e18);
    }
}
