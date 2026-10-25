// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/// @dev Every value here is copied from /home/slova/pegrecover/FACTS.md (measured on-chain 2026-10-25)
///      or was read via the public BSC RPC while preparing the fork test (recorded in README.md).
library Facts {
    // --- AGW deployment math (Abstract, ZK Stack) ---
    address internal constant AGW_FACTORY = 0x9B947df68D35281C972511B3E7BC875926f26C1A;
    bytes32 internal constant AGW_BYTECODE_HASH = 0x0100003316a98e88b9e8931575675eed8e30eee97abeff3816fb98333ab085bc;
    address internal constant AGW_IMPL = 0xaA3633B417483F932969edAef7CC4f1068f6Faa9;
    /// @dev keccak256(abi.encode(AGW_IMPL)); the BEP writer measured the 0x7dc432c8 prefix, tests assert the full value.
    bytes32 internal constant AGW_CONSTRUCTOR_INPUT_HASH = 0x7dc432c80a70eef32157607a2f46e38cf1d957673706133ced678b80fcbf7ca2;

    // Case A: the stranded account
    address internal constant CASE_A_OWNER = 0x07C65fE9f29A86B937604Fa8d20a3FAE19d7BE48;
    bytes32 internal constant CASE_A_SALT = 0x9c40f26d0e218dc6219fe7bae7b50af65cd87a6e1da558c4fa7bdaa33fad5185;
    address internal constant CASE_A_ADDR = 0x6Ae0145e60b073e8c47B922f16c0F9E71e3eFA86;
    uint256 internal constant CASE_A_BALANCE = 19998e18;
    // EVM CREATE2 with case-A inputs (shows the plain-EVM formula does not reproduce the address)
    address internal constant CASE_A_EVM_CREATE2 = 0xbE2b2FFe38B18B1094c1Cc24126aC140530F8D4f;

    // Case B: jojo's own AGW
    address internal constant CASE_B_OWNER = 0x349E6C340625A76F9C7Ef76ed826e66CBD5Bd7B4;
    bytes32 internal constant CASE_B_SALT = 0x83110841e6184847ecdb526795e56824ed672100843d4bbb7e5365aa7ea81e10;
    address internal constant CASE_B_ADDR = 0xDb85b9035a02E0cB60bDd33655612930Ab414838;

    // --- Binance-Peg USDC on BSC (EIP-1967 TransparentUpgradeableProxy) ---
    address internal constant BSC_USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address internal constant BSC_USDC_IMPL_V1 = 0xBA5Fe23f8a3a24BEd3236F05F2FcF35fd0BF0B5C;
    address internal constant BSC_USDC_PROXY_ADMIN = 0xD2f93484f2D319194cBa95C5171B18C1d8cfD6C4; // EOA
    address internal constant BSC_USDC_OWNER = 0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d;       // getOwner()
    address internal constant BINANCE_HOT_WALLET = 0xe2fc31F816A9b94326492132018C3aEcC4a93aE1;    // sender of the stranding tx

    bytes32 internal constant EIP1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant EIP1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev Read via `cast block-number` on https://bsc-dataseed.bnbchain.org while writing the fork test.
    uint256 internal constant FORK_BLOCK = 129782171;

    function agwConstructorInput() internal pure returns (bytes memory) {
        return abi.encode(AGW_IMPL);
    }
}
