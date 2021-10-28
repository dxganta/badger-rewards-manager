// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ISettV3 {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _shares) external;
    function withdrawAll() external;
}