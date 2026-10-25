// SPDX-License-Identifier: Apache-2.0
// Extends bnb-chain/canonical-upgradeable-bep20 BEP20TokenImplementation (Apache-2.0, see src/vendor/).
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./vendor/BEP20TokenImplementation.sol";
import "./ZkCreate2.sol";

/// @title BEP20TokenImplementationV2
/// @notice Binance-Peg BEP20 implementation V1 + recovery of tokens stranded at
///         ZKsync-derived smart-account addresses (e.g. Abstract Global Wallets)
///         that have no code on this chain.
///
/// @dev STORAGE: append-only. Every V1 slot (Initializable flags, _balances,
///      _allowances, _totalSupply, _name, _symbol, _decimals, _owner, _mintable)
///      keeps its position; the new state lives in slots after `_mintable`.
///      Compiled with solc 0.6.12 (same 0.6 line as the vendored V1) so
///      `forge inspect ... storage-layout` of V1 and V2 differ only by the
///      appended slots. See README.md for the diff.
///
///      V1 declares its state `private`, so V2 reads token name and balances
///      through external self-calls (`this.name()`, `this.balanceOf()`) and
///      moves balances through the inherited `_transfer`. The vendored V1
///      source is byte-identical to upstream.
///
/// @dev Recovery flow (anyone may submit, the signature authorises):
///      1. `d.factory` must have a registered OwnerScheme (set by the token owner).
///      2. ZKsync CREATE2(d) must derive `c.stranded`.
///      3. `c.stranded` has no code on this chain.
///      4. `block.timestamp <= c.deadline`, `c.nonce == recoveryNonce(c.stranded)` (then +1).
///      5. EIP-712 signature over RecoveryClaim recovers `signer` (no zero, no high-s).
///      6. SALT_IS_KECCAK_OF_INITIAL_OWNER: `keccak256(abi.encodePacked(signer)) == d.salt`.
///      7. `amount == 0` means the full balance. Balance moves stranded -> c.to.
contract BEP20TokenImplementationV2 is BEP20TokenImplementation {
    // ------------------------------------------------------------------ types

    enum OwnerScheme { NONE, SALT_IS_KECCAK_OF_INITIAL_OWNER }

    struct ZkDeployment {
        address factory;          // ZKsync-side deployer (msg.sender of the CREATE2)
        bytes32 salt;
        bytes32 bytecodeHash;     // ZKsync bytecode-hash format
        bytes constructorInput;
    }

    struct RecoveryClaim {
        address stranded;
        address to;
        uint256 amount;           // 0 = full balance
        uint256 nonce;
        uint256 deadline;
    }

    // -------------------------------------------------------------- constants

    /// @dev keccak256("RecoveryClaim(address stranded,address to,uint256 amount,uint256 nonce,uint256 deadline)")
    bytes32 public constant RECOVERY_CLAIM_TYPEHASH =
        0x835a1ddd6f21721e0341455f19d4804951b583f81b1c0e0418cb09db6a4e0057;

    /// @dev keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /// @dev keccak256("1")
    bytes32 private constant EIP712_VERSION_HASH =
        0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6;

    /// @dev secp256k1 n / 2 — signatures with s above this are rejected (EIP-2 malleability).
    uint256 private constant SECP256K1_HALF_N =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // ------------------------------------------------- appended storage (V2)

    /// @dev slot 7: factory => owner-binding scheme
    mapping(address => OwnerScheme) private _zkFactoryScheme;
    /// @dev slot 8: stranded address => next expected claim nonce
    mapping(address => uint256) private _recoveryNonce;
    /// @dev slots 9..56: reserved for future versions (append-only rule).
    uint256[48] private __gapV2;

    // ----------------------------------------------------------------- events

    event ZkFactorySchemeSet(address indexed factory, OwnerScheme scheme);
    event StrandedZkAccountRecovered(
        address indexed stranded,
        address indexed signer,
        address indexed to,
        uint256 amount,
        address factory
    );

    // ------------------------------------------------------------------ admin

    /// @notice Register (or clear, with NONE) the owner-binding scheme of a ZKsync factory.
    function setZkFactoryScheme(address factory, OwnerScheme scheme) external onlyOwner {
        require(factory != address(0), "V2: zero factory");
        _zkFactoryScheme[factory] = scheme;
        emit ZkFactorySchemeSet(factory, scheme);
    }

    // ------------------------------------------------------------------ views

    function zkFactoryScheme(address factory) external view returns (OwnerScheme) {
        return _zkFactoryScheme[factory];
    }

    function recoveryNonce(address stranded) external view returns (uint256) {
        return _recoveryNonce[stranded];
    }

    /// @notice ZKsync CREATE2 address for a deployment description.
    function zkCreate2Address(ZkDeployment calldata d) external pure returns (address) {
        return _zkCreate2Address(d);
    }

    /// @notice EIP-712 domain separator: (name(), "1", chainid, address(this)).
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /// @notice EIP-712 digest a claim must be signed over.
    function recoveryClaimDigest(RecoveryClaim calldata c) external view returns (bytes32) {
        return _digest(c);
    }

    // --------------------------------------------------------------- recovery

    function recoverStrandedZkAccount(
        ZkDeployment calldata d,
        RecoveryClaim calldata c,
        bytes calldata signature
    ) external {
        OwnerScheme scheme = _zkFactoryScheme[d.factory];
        require(scheme != OwnerScheme.NONE, "V2: factory not registered");
        require(_zkCreate2Address(d) == c.stranded, "V2: derivation mismatch");
        require(!_hasCode(c.stranded), "V2: stranded address has code");
        require(block.timestamp <= c.deadline, "V2: claim expired");
        require(c.nonce == _recoveryNonce[c.stranded], "V2: bad nonce");
        _recoveryNonce[c.stranded] = c.nonce + 1;

        address signer = _recoverSigner(_digest(c), signature);
        require(signer != address(0), "V2: zero signer");
        if (scheme == OwnerScheme.SALT_IS_KECCAK_OF_INITIAL_OWNER) {
            require(keccak256(abi.encodePacked(signer)) == d.salt, "V2: signer is not the initial owner");
        } else {
            revert("V2: unknown scheme");
        }

        uint256 amount = c.amount;
        if (amount == 0) {
            amount = this.balanceOf(c.stranded);
        }
        require(amount > 0, "V2: nothing to recover");

        // inherited V1 internal: checks sender/recipient != 0, balance >= amount, emits Transfer
        _transfer(c.stranded, c.to, amount);
        emit StrandedZkAccountRecovered(c.stranded, signer, c.to, amount, d.factory);
    }

    // -------------------------------------------------------------- internals

    function _zkCreate2Address(ZkDeployment calldata d) internal pure returns (address) {
        return ZkCreate2.zkCreate2Address(d.factory, d.salt, d.bytecodeHash, d.constructorInput);
    }

    function _hasCode(address a) internal view returns (bool) {
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(a) }
        return size > 0;
    }

    function _chainId() internal pure returns (uint256 id) {
        // solhint-disable-next-line no-inline-assembly
        assembly { id := chainid() }
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(this.name())),
                EIP712_VERSION_HASH,
                _chainId(),
                address(this)
            )
        );
    }

    function _digest(RecoveryClaim calldata c) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(RECOVERY_CLAIM_TYPEHASH, c.stranded, c.to, c.amount, c.nonce, c.deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        require(signature.length == 65, "V2: bad signature length");
        // solc 0.6 has no `.offset` for calldata bytes; calldata slices do the job.
        bytes32 r = abi.decode(signature[0:32], (bytes32));
        bytes32 s = abi.decode(signature[32:64], (bytes32));
        uint8 v = uint8(signature[64]);
        require(uint256(s) <= SECP256K1_HALF_N, "V2: bad signature s");
        require(v == 27 || v == 28, "V2: bad signature v");
        return ecrecover(digest, v, r, s);
    }
}
