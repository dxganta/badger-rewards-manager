// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBadgerTreeV2 {
    function notifyTransfer(uint256 _amount, address _from, address _to) external;
}