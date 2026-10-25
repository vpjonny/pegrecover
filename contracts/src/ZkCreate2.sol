// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.6.0 <0.9.0;

/// @title ZkCreate2
/// @notice Pure address-derivation helpers for ZKsync-style (EraVM) CREATE2 and
///         plain EVM CREATE2. No storage, no external calls.
/// @dev ZKsync CREATE2 (ContractDeployer.getNewAddressCreate2):
///      address = keccak256(
///          keccak256("zksyncCreate2")
///          ++ bytes32(uint160(deployer))
///          ++ salt
///          ++ bytecodeHash            // ZKsync bytecode-hash format (version byte 0x01 ...)
///          ++ keccak256(constructorInput)
///      )[12:]
library ZkCreate2 {
    /// @dev keccak256("zksyncCreate2")
    bytes32 internal constant ZKSYNC_CREATE2_PREFIX =
        0x2020dba91b30cc0006188af794c2fb30dd8520db7e2c088b7fc7c103c00ca494;

    /// @notice Address a ZKsync ContractDeployer assigns to `deployer`'s CREATE2 with these inputs.
    function zkCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash,
        bytes memory constructorInput
    ) internal pure returns (address) {
        bytes32 h = keccak256(
            abi.encodePacked(
                ZKSYNC_CREATE2_PREFIX,
                bytes32(uint256(uint160(deployer))),
                salt,
                bytecodeHash,
                keccak256(constructorInput)
            )
        );
        return address(uint160(uint256(h)));
    }

    /// @notice Plain EVM CREATE2: keccak256(0xff ++ deployer ++ salt ++ initCodeHash)[12:].
    ///         Included so tests can show the EVM formula does NOT reproduce the ZKsync address.
    function evmCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        bytes32 h = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash));
        return address(uint160(uint256(h)));
    }
}
