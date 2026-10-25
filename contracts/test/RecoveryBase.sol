// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ZkCreate2} from "../src/ZkCreate2.sol";
import {
    IBEP20TokenImplementationV2 as IV2,
    ITransparentUpgradeableProxy
} from "../src/interfaces/IBEP20TokenImplementationV2.sol";
import {Facts} from "./Facts.sol";

/// @dev Shared helpers. The implementation contracts are solc 0.6.12, the tests 0.8.x,
///      so V1/V2/proxy are deployed from their compiled artifacts (vm.getCode) and
///      driven through the 0.8 interface.
abstract contract RecoveryBase is Test {
    string internal constant V1_ARTIFACT = "BEP20TokenImplementation.sol:BEP20TokenImplementation";
    string internal constant V2_ARTIFACT = "BEP20TokenImplementationV2.sol:BEP20TokenImplementationV2";
    string internal constant PROXY_ARTIFACT = "BEP20UpgradeableProxy.sol:BEP20UpgradeableProxy";

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant RECOVERY_CLAIM_TYPEHASH =
        keccak256("RecoveryClaim(address stranded,address to,uint256 amount,uint256 nonce,uint256 deadline)");
    uint256 internal constant SECP256K1_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function deployV2() internal returns (address) {
        return deployCode(V2_ARTIFACT);
    }

    function agwDeployment(bytes32 salt) internal pure returns (IV2.ZkDeployment memory d) {
        d = IV2.ZkDeployment({
            factory: Facts.AGW_FACTORY,
            salt: salt,
            bytecodeHash: Facts.AGW_BYTECODE_HASH,
            constructorInput: Facts.agwConstructorInput()
        });
    }

    /// @dev AGW-style derivation for an initial owner: salt = keccak256(owner).
    function agwAddressFor(address initialOwner) internal pure returns (address stranded, bytes32 salt) {
        salt = keccak256(abi.encodePacked(initialOwner));
        stranded = ZkCreate2.zkCreate2Address(
            Facts.AGW_FACTORY, salt, Facts.AGW_BYTECODE_HASH, Facts.agwConstructorInput()
        );
    }

    /// @dev Independent (test-side) EIP-712 digest, compared against the contract's view in tests.
    function claimDigest(IV2 token, IV2.RecoveryClaim memory c) internal view returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(token.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(RECOVERY_CLAIM_TYPEHASH, c.stranded, c.to, c.amount, c.nonce, c.deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function signClaim(IV2 token, IV2.RecoveryClaim memory c, uint256 pk) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, claimDigest(token, c));
        return abi.encodePacked(r, s, v);
    }
}
