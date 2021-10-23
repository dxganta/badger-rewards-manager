// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IBadgerTreeV2 {
    /// @notice Info of each sett.
    struct SettInfo {
        uint64 lastRewardBlock; // the last block when the reward p were updated
        uint64 endingBlock; // ending timestamp for current reward cycle
        uint128 accBadgerPerShare; // number of tokens accumulated per share till lastRewardBlock
        uint128 badgerPerBlock; // number of reward token per block 
        address[] rewardTokens;  // address of all the reward tokens
        uint128[] totalTokens; // total number of emitted tokens till now. totalTokens[0] is for total emitted badgers. rest is for the other reward Tokens
    }
    function notifyTransfer(uint256 _amount, address _from, address _to) external;
    function updateSett(address _sett) external returns (SettInfo memory sett);
}