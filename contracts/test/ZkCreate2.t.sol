// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ZkCreate2} from "../src/ZkCreate2.sol";
import {Facts} from "./Facts.sol";

contract ZkCreate2Test is Test {
    function test_prefixIsKeccakOfZksyncCreate2() public pure {
        assertEq(ZkCreate2.ZKSYNC_CREATE2_PREFIX, keccak256("zksyncCreate2"));
    }

    function test_caseA_saltIsKeccakOfInitialOwner() public pure {
        assertEq(keccak256(abi.encodePacked(Facts.CASE_A_OWNER)), Facts.CASE_A_SALT);
    }

    function test_caseB_saltIsKeccakOfInitialOwner() public pure {
        assertEq(keccak256(abi.encodePacked(Facts.CASE_B_OWNER)), Facts.CASE_B_SALT);
    }

    function test_caseA_zkCreate2Address() public pure {
        address a = ZkCreate2.zkCreate2Address(
            Facts.AGW_FACTORY, Facts.CASE_A_SALT, Facts.AGW_BYTECODE_HASH, Facts.agwConstructorInput()
        );
        assertEq(a, Facts.CASE_A_ADDR);
    }

    function test_caseB_zkCreate2Address() public pure {
        address a = ZkCreate2.zkCreate2Address(
            Facts.AGW_FACTORY, Facts.CASE_B_SALT, Facts.AGW_BYTECODE_HASH, Facts.agwConstructorInput()
        );
        assertEq(a, Facts.CASE_B_ADDR);
    }

    function test_caseA_evmCreate2DoesNotReproduceAddress() public pure {
        address evm = ZkCreate2.evmCreate2Address(Facts.AGW_FACTORY, Facts.CASE_A_SALT, Facts.AGW_BYTECODE_HASH);
        assertEq(evm, Facts.CASE_A_EVM_CREATE2);
        assertTrue(evm != Facts.CASE_A_ADDR);
    }

    function test_differentSaltDifferentAddress() public pure {
        address a = ZkCreate2.zkCreate2Address(
            Facts.AGW_FACTORY, Facts.CASE_A_SALT, Facts.AGW_BYTECODE_HASH, Facts.agwConstructorInput()
        );
        address b = ZkCreate2.zkCreate2Address(
            Facts.AGW_FACTORY, Facts.CASE_B_SALT, Facts.AGW_BYTECODE_HASH, Facts.agwConstructorInput()
        );
        assertTrue(a != b);
    }
}
