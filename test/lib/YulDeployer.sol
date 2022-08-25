// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

/// @dev Inspired by https://github.com/CodeForcer/foundry-yul/blob/main/test/lib/YulDeployer.sol
contract YulDeployer is Test {
    ///@notice Compiles a Yul contract and returns the address that the contract was deployed to
    ///@notice If deployment fails, an error will be thrown
    ///@param fileName - The file name of the Yul contract. For example, the file name for "Example.yul" is "Example"
    ///@param constructorArgs - The abi encoded constructor args
    ///@return deployedAddress - The address that the contract was deployed to
    function deployContract(string memory fileName, bytes memory constructorArgs) public returns (address) {
        string memory bashCommand = string.concat('cast abi-encode "f(bytes)" $(solc --yul yul/', string.concat(fileName, ".yul --bin | tail -1)"));

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = bashCommand;

        bytes memory bytecode = abi.decode(vm.ffi(inputs), (bytes));

        ///@notice append the constructor arguments to the creation bytecode
        bytes memory bytecodeToDeploy = bytes.concat(bytecode, constructorArgs);

        ///@notice deploy the bytecode with the create instruction
        address deployedAddress;
        assembly {
            deployedAddress := create(0, add(bytecodeToDeploy, 0x20), mload(bytecodeToDeploy))
        }

        ///@notice check that the deployment was successful
        require(
            deployedAddress != address(0),
            "YulDeployer could not deploy contract"
        );

        ///@notice return the address that the contract was deployed to
        return deployedAddress;
    }
}
