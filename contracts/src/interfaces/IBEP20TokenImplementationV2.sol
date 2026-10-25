// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

/// @notice 0.8-compatible ABI of BEP20TokenImplementationV2 (the implementation itself is solc 0.6.12).
///         Used by the Foundry tests and handy for integrators / relayers.
interface IBEP20TokenImplementationV2 {
    enum OwnerScheme { NONE, SALT_IS_KECCAK_OF_INITIAL_OWNER }

    struct ZkDeployment { address factory; bytes32 salt; bytes32 bytecodeHash; bytes constructorInput; }
    struct RecoveryClaim { address stranded; address to; uint256 amount; uint256 nonce; uint256 deadline; }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ZkFactorySchemeSet(address indexed factory, OwnerScheme scheme);
    event StrandedZkAccountRecovered(
        address indexed stranded, address indexed signer, address indexed to, uint256 amount, address factory
    );

    // V1 surface
    function initialize(string memory name, string memory symbol, uint8 decimals, uint256 amount, bool mintable, address owner) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function getOwner() external view returns (address);
    function mintable() external view returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function mint(uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;

    // V2 surface
    function RECOVERY_CLAIM_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function recoveryClaimDigest(RecoveryClaim calldata c) external view returns (bytes32);
    function setZkFactoryScheme(address factory, OwnerScheme scheme) external;
    function zkFactoryScheme(address factory) external view returns (OwnerScheme);
    function recoveryNonce(address stranded) external view returns (uint256);
    function recoverStrandedZkAccount(ZkDeployment calldata d, RecoveryClaim calldata c, bytes calldata signature) external;
    function zkCreate2Address(ZkDeployment calldata d) external pure returns (address);
}

/// @notice Admin surface of OpenZeppelin v3.2.0 TransparentUpgradeableProxy (what BEP20UpgradeableProxy is).
interface ITransparentUpgradeableProxy {
    event Upgraded(address indexed implementation);
    function admin() external returns (address);
    function implementation() external returns (address);
    function changeAdmin(address newAdmin) external;
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}
