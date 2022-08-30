// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { Test, console2 } from "forge-std/Test.sol";
import { HuffDeployer } from "huff-language/HuffDeployer.sol";

import { ERC20 } from "src/ERC20.sol";
import { YulDeployer } from "./lib/YulDeployer.sol";

abstract contract TestHelper is Test {

    string constant tokenName = "Token";
    string constant tokenNameLong = "How does the EVM work? We explain the relationship between opcode instructions, gas costs, storage and the execution environment for your understanding.";
    string constant tokenSymbol = "TK";
    address constant alice = address(0xa11ce);
    address constant bob = address(0xb0b);

    ERC20 token;

    function deployToken(string memory name, string memory symbol) internal virtual returns (ERC20);

    function setUp() external {
        token = deployToken(tokenName, tokenSymbol);
    }

    function testName() external {
        // Test string packing
        assertEq(token.name(), tokenName);
        // Test string not packed
        ERC20 t = deployToken(tokenNameLong, tokenSymbol);
        assertEq(t.name(), tokenNameLong);
    }

    function testSymbol() external {
        assertEq(token.symbol(), tokenSymbol);
    }

    function testOwner() external {
        assertEq(token.owner(), address(this));
    }

    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    function testMint() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(address(0), alice, 2e18);
        token.mint(alice, 2e18);
        assertEq(token.totalSupply(), token.balanceOf(alice));
    }

    function testBurn() public {
        token.mint(alice, 10e18);
        assertEq(token.balanceOf(alice), 10e18);

        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(alice, address(0), 8e18);
        token.burn(alice, 8e18);

        assertEq(token.totalSupply(), 2e18);
        assertEq(token.balanceOf(alice), 2e18);
    }

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    function testApprove() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Approval(address(this), alice, 1e18);
        assertTrue(token.approve(alice, 1e18));
        assertEq(token.allowance(address(this), alice), 1e18);
    }

    function testTransfer() external {
        testMint();
        vm.startPrank(alice);
        token.transfer(bob, 0.5e18);
        assertEq(token.balanceOf(bob), 0.5e18);
        assertEq(token.balanceOf(alice), 1.5e18);
        vm.stopPrank();
    }

    function testTransferFrom() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), 1e18);
        assertTrue(token.transferFrom(alice, bob, 0.7e18));
        assertEq(token.allowance(alice, address(this)), 1e18 - 0.7e18);
        assertEq(token.balanceOf(alice), 2e18 - 0.7e18);
        assertEq(token.balanceOf(bob), 0.7e18);
    }

    function testFailBurnInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.burn(alice, 3e18);
    }

    function testFailTransferInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.transfer(bob, 3e18);
    }

    function testFailTransferFromInsufficientApprove() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), 1e18);
        token.transferFrom(alice, bob, 2e18);
    }

    function testFailTransferFromInsufficientBalance() external {
        testMint();
        vm.prank(alice);
        token.approve(address(this), type(uint256).max);

        token.transferFrom(alice, bob, 3e18);
    }

    /* --- FUZZ TESTING --- */

    function testFuzzMint(address to, uint256 amount) external {
        vm.assume(to != address(0));
        token.mint(to, amount);
        assertEq(token.totalSupply(), token.balanceOf(to));
    }

    function testFuzzBurn(address from, uint256 mintAmount, uint256 burnAmount)
        external
    {
        vm.assume(from != address(0)); // from address must not zero
        burnAmount = bound(burnAmount, 0, mintAmount); // if burnAmount > mintAmount then bound burnAmount to 0 to mintAmount
        token.mint(from, mintAmount);
        token.burn(from, burnAmount);
        assertEq(token.totalSupply(), mintAmount - burnAmount);
        assertEq(token.balanceOf(from), mintAmount - burnAmount);
    }

    function testFuzzApprove(address to, uint256 amount) external {
        vm.assume(to != address(0));
        assertTrue(token.approve(to, amount));
        assertEq(token.allowance(address(this), to), amount);
    }

    function testFuzzTransfer(address to, uint256 amount) external {
        vm.assume(to != address(0));
        vm.assume(to != address(this));
        token.mint(address(this), amount);

        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(to), amount);
    }

    function testFuzzTransferFrom(
        address from,
        address to,
        uint256 approval,
        uint256 amount
    )
        external
    {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != to);

        amount = bound(amount, 0, approval);
        token.mint(from, amount);

        vm.prank(from);
        assertTrue(token.approve(address(this), approval));

        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.totalSupply(), amount);

        assertEq(token.allowance(from, address(this)), approval - amount);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(to), amount);
    }

    function testFailFuzzBurnInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 burnAmount
    )
        external
    {
        burnAmount = bound(burnAmount, mintAmount + 1, type(uint256).max);

        token.mint(to, mintAmount);
        token.burn(to, burnAmount);
    }

    function testFailTransferInsufficientBalance(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    )
        external
    {
        sendAmount = bound(sendAmount, mintAmount + 1, type(uint256).max);

        token.mint(address(this), mintAmount);
        token.transfer(to, sendAmount);
    }

    function testFailFuzzTransferFromInsufficientApprove(
        address from,
        address to,
        uint256 approval,
        uint256 amount
    )
        external
    {
        amount = bound(amount, approval + 1, type(uint256).max);

        token.mint(from, amount);
        vm.prank(from);
        token.approve(address(this), approval);
        token.transferFrom(from, to, amount);
    }

    function testFailFuzzTransferFromInsufficientBalance(
        address from,
        address to,
        uint256 mintAmount,
        uint256 sentAmount
    )
        external
    {
        sentAmount = bound(sentAmount, mintAmount + 1, type(uint256).max);

        token.mint(from, mintAmount);
        vm.prank(from);
        token.approve(address(this), type(uint256).max);

        token.transferFrom(from, to, sentAmount);
    }
}

contract ERC20SolTest is Test, TestHelper {

    function deployToken(string memory name, string memory symbol) internal override returns (ERC20) {
        return new ERC20(name, symbol);
    }
}

contract ERC20YulTest is Test, TestHelper {

    YulDeployer yulDeployer = new YulDeployer();

    function deployToken(string memory name, string memory symbol) internal override returns (ERC20) {
        bytes memory constructorArgs = abi.encode(name, symbol);

        // Need to delegatecall so token owner is address(this)
        (bool success, bytes memory b) = address(yulDeployer)
            .delegatecall(abi.encodeCall(yulDeployer.deployContract, ("ERC20", constructorArgs)));
        require(success);
        return ERC20(abi.decode(b, (address)));
    }
}

contract ERC20HuffTest is Test, TestHelper {

    function deployToken(string memory name, string memory symbol) internal override returns (ERC20) {
        address addr = HuffDeployer
            .config()
            .with_args(abi.encode(name, symbol))
            .deploy("huff/ERC20");
        return ERC20(addr);
    }

    function testStorage() external {
        console2.logBytes(address(token).code);
        console2.logBytes32(vm.load(address(token), bytes32(uint256(0x00))));
        console2.logBytes32(vm.load(address(token), bytes32(uint256(0x01))));
        assertEq(uint256(vm.load(address(token), 0)), 0x12345);
    }
}
