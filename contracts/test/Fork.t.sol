// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import {RecoveryBase, IV2, ITransparentUpgradeableProxy, Facts} from "./RecoveryBase.sol";

/// @notice BSC mainnet fork: upgrade the real Binance-Peg USDC proxy to V2 as its admin,
///         prove V1 storage is intact, and demonstrate a recovery.
///         Fork pinned at Facts.FORK_BLOCK = 129782171 (read via the public RPC).
contract ForkTest is RecoveryBase {
    IV2 internal usdc = IV2(Facts.BSC_USDC);
    address internal relayer = makeAddr("relayer");
    address internal beneficiary = makeAddr("beneficiary");

    function setUp() public {
        vm.createSelectFork("bsc", Facts.FORK_BLOCK);
        assertEq(block.chainid, 56);
    }

    function _implSlot() internal view returns (address) {
        return address(uint160(uint256(vm.load(Facts.BSC_USDC, Facts.EIP1967_IMPL_SLOT))));
    }

    function _upgradeToV2() internal returns (address v2) {
        v2 = deployV2();
        vm.prank(Facts.BSC_USDC_PROXY_ADMIN);
        ITransparentUpgradeableProxy(Facts.BSC_USDC).upgradeTo(v2);
    }

    function test_fork_caseA_isStrandedAtForkBlock() public view {
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);
        assertEq(Facts.CASE_A_ADDR.code.length, 0);
        assertEq(_implSlot(), Facts.BSC_USDC_IMPL_V1);
        assertEq(address(uint160(uint256(vm.load(Facts.BSC_USDC, Facts.EIP1967_ADMIN_SLOT)))), Facts.BSC_USDC_PROXY_ADMIN);
        assertEq(usdc.getOwner(), Facts.BSC_USDC_OWNER);
    }

    function test_fork_upgradePreservesStorage() public {
        string memory name0 = usdc.name();
        string memory symbol0 = usdc.symbol();
        uint8 dec0 = usdc.decimals();
        uint256 supply0 = usdc.totalSupply();
        address owner0 = usdc.getOwner();
        uint256 hot0 = usdc.balanceOf(Facts.BINANCE_HOT_WALLET);

        address v2 = _upgradeToV2();
        assertEq(_implSlot(), v2);

        assertEq(usdc.name(), name0);
        assertEq(usdc.symbol(), symbol0);
        assertEq(usdc.decimals(), dec0);
        assertEq(usdc.totalSupply(), supply0);
        assertEq(usdc.getOwner(), owner0);
        assertEq(usdc.balanceOf(Facts.BINANCE_HOT_WALLET), hot0);
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);

        // V2 state starts clean
        (IV2.OwnerScheme sch, bytes32 bh, bytes32 cih) = usdc.zkFactoryScheme(Facts.AGW_FACTORY);
        assertEq(uint8(sch), uint8(IV2.OwnerScheme.NONE));
        assertEq(bh, bytes32(0));
        assertEq(cih, bytes32(0));
        assertEq(usdc.recoveryNonce(Facts.CASE_A_ADDR), 0);
        assertEq(usdc.zkCreate2Address(agwDeployment(Facts.CASE_A_SALT)), Facts.CASE_A_ADDR);
    }

    function test_fork_upgradeOnlyByProxyAdmin() public {
        address v2 = deployV2();
        vm.prank(Facts.BSC_USDC_OWNER); // token owner is not the proxy admin
        vm.expectRevert();
        ITransparentUpgradeableProxy(Facts.BSC_USDC).upgradeTo(v2);
        assertEq(_implSlot(), Facts.BSC_USDC_IMPL_V1);
    }

    function test_fork_registerSchemeOnlyByTokenOwner() public {
        _upgradeToV2();
        vm.prank(relayer);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        usdc.setZkFactoryScheme(
            Facts.AGW_FACTORY, IV2.OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER, Facts.AGW_BYTECODE_HASH, Facts.AGW_CONSTRUCTOR_INPUT_HASH
        );
    }

    function test_fork_recoverFreshAgwAddress() public {
        _upgradeToV2();
        registerAgw(usdc, Facts.BSC_USDC_OWNER);
        assertAgwRegistered(usdc);

        // a fresh initial-owner key whose AGW-style address we can sign for
        (address freshOwner, uint256 freshPk) = makeAddrAndKey("fresh initial owner on fork");
        (address stranded, bytes32 salt) = agwAddressFor(freshOwner);
        assertEq(stranded.code.length, 0);
        assertEq(usdc.balanceOf(stranded), 0);

        // strand tokens there the way case A happened: a transfer from the Binance hot wallet
        uint256 amount = 1_234e18;
        uint256 hotBefore = usdc.balanceOf(Facts.BINANCE_HOT_WALLET);
        assertGe(hotBefore, amount);
        vm.prank(Facts.BINANCE_HOT_WALLET);
        usdc.transfer(stranded, amount);
        assertEq(usdc.balanceOf(stranded), amount);

        IV2.RecoveryClaim memory c = IV2.RecoveryClaim({
            stranded: stranded, to: beneficiary, amount: 0, nonce: 0, deadline: block.timestamp + 7 days
        });
        assertEq(usdc.recoveryClaimDigest(c), claimDigest(usdc, c));
        bytes memory sig = signClaim(usdc, c, freshPk);

        uint256 supply0 = usdc.totalSupply();
        vm.expectEmit(true, true, true, true, Facts.BSC_USDC);
        emit IV2.Transfer(stranded, beneficiary, amount);
        vm.expectEmit(true, true, true, true, Facts.BSC_USDC);
        emit IV2.StrandedZkAccountRecovered(stranded, freshOwner, beneficiary, amount, Facts.AGW_FACTORY);
        vm.prank(relayer);
        uint256 g = gasleft();
        usdc.recoverStrandedZkAccount(agwDeployment(salt), c, sig);
        g -= gasleft();
        emit log_named_uint("gas: relayer->proxy recoverStrandedZkAccount (full balance, fork)", g);

        assertEq(usdc.balanceOf(stranded), 0);
        assertEq(usdc.balanceOf(beneficiary), amount);
        assertEq(usdc.totalSupply(), supply0);
        assertEq(usdc.recoveryNonce(stranded), 1);
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE, "case A untouched");
    }

    function test_fork_caseA_randomKeyRejected() public {
        _upgradeToV2();
        registerAgw(usdc, Facts.BSC_USDC_OWNER);
        assertAgwRegistered(usdc);

        (, uint256 randomPk) = makeAddrAndKey("not the case A owner");
        IV2.RecoveryClaim memory c = IV2.RecoveryClaim({
            stranded: Facts.CASE_A_ADDR, to: beneficiary, amount: 0, nonce: 0, deadline: block.timestamp + 7 days
        });
        bytes memory sig = signClaim(usdc, c, randomPk);
        vm.prank(relayer);
        vm.expectRevert(bytes("V2: signer is not the initial owner"));
        usdc.recoverStrandedZkAccount(agwDeployment(Facts.CASE_A_SALT), c, sig);
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);
    }

    function test_fork_caseA_claimPassesEveryCheckExceptSignature() public {
        // Everything but the initial owner's signature is satisfied for case A on BSC:
        _upgradeToV2();
        registerAgw(usdc, Facts.BSC_USDC_OWNER);
        IV2.ZkDeployment memory d = agwDeployment(Facts.CASE_A_SALT);
        (, bytes32 bh, bytes32 cih) = usdc.zkFactoryScheme(Facts.AGW_FACTORY);
        assertEq(d.bytecodeHash, bh);                                                            // pinned bytecode hash
        assertEq(keccak256(d.constructorInput), cih);                                            // pinned constructor input
        assertEq(cih, keccak256(abi.encode(Facts.AGW_IMPL)));
        assertEq(usdc.zkCreate2Address(d), Facts.CASE_A_ADDR);                                   // derivation
        assertEq(Facts.CASE_A_ADDR.code.length, 0);                                           // no code on BSC
        assertEq(keccak256(abi.encodePacked(Facts.CASE_A_OWNER)), Facts.CASE_A_SALT);         // owner binding
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);                   // funds
    }

    function test_fork_caseA_wrongBytecodeHashRejected() public {
        _upgradeToV2();
        registerAgw(usdc, Facts.BSC_USDC_OWNER);
        (, uint256 pk) = makeAddrAndKey("any key");
        IV2.RecoveryClaim memory c = IV2.RecoveryClaim({
            stranded: Facts.CASE_A_ADDR, to: beneficiary, amount: 0, nonce: 0, deadline: block.timestamp + 7 days
        });
        bytes memory sig = signClaim(usdc, c, pk);
        IV2.ZkDeployment memory d = agwDeployment(Facts.CASE_A_SALT);
        d.bytecodeHash = keccak256("not the AGW account bytecode");
        vm.expectRevert(bytes("V2: bytecode hash not pinned for factory"));
        usdc.recoverStrandedZkAccount(d, c, sig);
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);
    }

    function test_fork_caseA_wrongConstructorInputRejected() public {
        _upgradeToV2();
        registerAgw(usdc, Facts.BSC_USDC_OWNER);
        (, uint256 pk) = makeAddrAndKey("any key");
        IV2.RecoveryClaim memory c = IV2.RecoveryClaim({
            stranded: Facts.CASE_A_ADDR, to: beneficiary, amount: 0, nonce: 0, deadline: block.timestamp + 7 days
        });
        bytes memory sig = signClaim(usdc, c, pk);
        IV2.ZkDeployment memory d = agwDeployment(Facts.CASE_A_SALT);
        d.constructorInput = abi.encode(makeAddr("not the AGW impl"));
        vm.expectRevert(bytes("V2: constructor input not pinned for factory"));
        usdc.recoverStrandedZkAccount(d, c, sig);
        assertEq(usdc.balanceOf(Facts.CASE_A_ADDR), Facts.CASE_A_BALANCE);
    }
}
