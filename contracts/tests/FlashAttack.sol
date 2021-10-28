// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/ISettV3.sol";
import "../../interfaces/token/IERC20.sol";

// contract to test that a same block deposit & withdraw
// would give zero rewards

contract FlashAttack {
    address sett;

    constructor(address _sett) {
        sett = _sett;
    }

    function attack(uint256 _amount, address _want) public {
        IERC20(_want).approve(sett, _amount);
        ISettV3(sett).deposit(_amount);
        ISettV3(sett).withdrawAll();
    }
}