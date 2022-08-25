// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

contract ERC20 {
    // Solidity creates the getters
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) public balanceOf; // Owner => balance
    mapping(address => mapping(address => uint256)) public allowance; // Owner => spender => allowance

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(
        address indexed _owner, address indexed _spender, uint256 _value
    );

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
    }

    function mint(address _to, uint256 _value) public onlyOwner {
        // Solidity checks it doesn't overflow
        totalSupply += _value;
        balanceOf[_to] += _value;

        emit Transfer(address(0), address(_to), _value);
    }

    function burn(address _to, uint256 _value) public onlyOwner {
        // Solidity checks it doesn't overflow
        totalSupply -= _value;
        balanceOf[_to] -= _value;

        emit Transfer(address(_to), address(0), _value);
    }

    function transfer(address _to, uint256 _value)
        public
        returns (bool success)
    {
        success = _transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value)
        public
        returns (bool success)
    {
        // Solidity checks the underflow error => (allowance -= value) >= 0
        allowance[_from][msg.sender] -= _value;
        success = _transfer(_from, _to, _value);
    }

    function _transfer(address _from, address _to, uint256 _value)
        internal
        returns (bool success)
    {
        // Solidity checks the underflow error => (balance -= value) >= 0
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        success = true;
        emit Transfer(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value)
        public
        returns (bool success)
    {
        allowance[msg.sender][_spender] = _value;
        success = true;
        emit Approval(msg.sender, _spender, _value);
    }
}
