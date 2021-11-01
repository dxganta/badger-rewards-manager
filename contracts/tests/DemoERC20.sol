// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../deps/@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DemoERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {

    }

    function mint(address account, uint amount) public {
        _mint(account, amount);
    }
}