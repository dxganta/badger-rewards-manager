// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/BoringBatchable.sol";
import "../interfaces/BoringOwnable.sol";
import "../interfaces/token/IERC20.sol";
import "./interfaces/ISettV3.sol";
import "../libraries/BoringERC20.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// DIFFERENT RATES OF EMISSIONS PER BLOCK PER SET


// NOTE: when adding a vault for the first time, if its lpSupply is zero but badgerPerBlock > 0, there are badgers lost till the lpSupply > 0


// dont even need a badger_per_block
// just put some badgers give the duration (in seconds) till which you want these
// badgers to complete & the function will automatically calculate the badger_reward_per_block

contract BadgerTreeV2 is BoringBatchable, BoringOwnable, PausableUpgradeable  {
    using BoringERC20 for IERC20;

    /// @notice Info of each user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of BADGER that the user has withdrawn
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each sett.
    struct SettInfo {
        uint128 accBadgerPerShare;
        uint64 lastRewardBlock;
        uint64 endingTimeStamp;
        uint128 badgerPerBlock; 
        uint256 lpSupply; // total deposits into that sett
    }

    /// @notice Address of BADGER contract.
    IERC20 public immutable BADGER;

    /// @notice Info of each sett. settAddress => settInfo
    mapping(address => SettInfo) public settInfo;

    /// @notice Info of each user that stakes Vault tokens. settAddress => userAddress => UserInfo
    mapping (address => mapping (address => UserInfo)) public userInfo;

    uint64 private constant PRECISION = 1e12;
    uint64 public BLOCK_TIME = 15; // block time in seconds

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, address indexed settAddress, uint256 amount);
    event LogSettAddition(address indexed settAddress);
    event LogSetSett(address indexed settAddress, uint256 allocPoint);
    event LogUpdateSett(address indexed settAddress, uint64 lastRewardBlock, uint256 lpSupply, uint256 accBadgerPerShare);

    /// @param _badger The BADGER token contract address.
    constructor(IERC20 _badger) {
        BADGER = _badger;
    }

    /// @notice set the block time for the current blockchain
    function setBlockTime(uint64 _val) external onlyOwner {
        BLOCK_TIME = _val;
    }

    function add(address _settAddress) public onlyOwner {
        uint256 lastRewardBlock = block.number;

        settInfo[_settAddress] = SettInfo({
            lastRewardBlock: uint64(lastRewardBlock),
            accBadgerPerShare: 0,
            lpSupply: 0,
            endingTimeStamp: 0,
            badgerPerBlock: 0
        });

        emit LogSettAddition(_settAddress);
    }

    function addSettRewards(address _settAddress, uint256 _amount, uint64 _duration) public onlyOwner {
        SettInfo storage _set = settInfo[_settAddress];
        require(block.timestamp >= _set.endingTimeStamp, "Rewards cycle not over");
        BADGER.safeTransfer(address(this), _amount);
        _set.endingTimeStamp = uint64(block.timestamp) + _duration;
        _set.badgerPerBlock = uint128(_amount / (_duration / BLOCK_TIME));
    }

    /// @notice View function to see pending BADGER on frontend.
    /// @param _sett The contract address of the sett
    /// @param _user Address of user.
    /// @return pending BADGER reward for a given user.
    function pendingBadger(address _sett, address _user) external view returns (uint256 pending) {
        SettInfo memory sett = settInfo[_sett];
        UserInfo storage user = userInfo[_sett][_user];
        uint256 accBadgerPerShare = sett.accBadgerPerShare;
        if (block.number > sett.lastRewardBlock && sett.lpSupply != 0) {
            uint256 blocks = block.number - sett.lastRewardBlock;
            uint256 badgerReward = blocks * sett.badgerPerBlock;
            accBadgerPerShare = accBadgerPerShare + ((badgerReward * PRECISION) / sett.lpSupply);
        }
        pending = uint256(int256((user.amount * accBadgerPerShare) / PRECISION) - user.rewardDebt);
    }

    /// @notice Update reward variables of the given sett.
    /// @param _settAddress The address of the set
    /// @return sett Returns the sett that was updated.
    function updateSett(address _settAddress) public returns (SettInfo memory sett) {
        sett = settInfo[_settAddress];
        if (block.number > sett.lastRewardBlock && block.timestamp < sett.endingTimeStamp) {
            if (sett.lpSupply > 0) {
                uint256 blocks = block.number - sett.lastRewardBlock;
                uint256 badgerReward = blocks * sett.badgerPerBlock;
                sett.accBadgerPerShare += uint128((badgerReward * PRECISION) / sett.lpSupply);
            }
            sett.lastRewardBlock = uint64(block.number);
            settInfo[_settAddress] = sett;
            emit LogUpdateSett(_settAddress, sett.lastRewardBlock, sett.lpSupply, sett.accBadgerPerShare);
        }
    }

    // can be called only by vault
    function notifyTransfer(uint256 _pid, uint256 _amount, address _from, address _to) public {
        SettInfo memory sett = updateSett(msg.sender);
        UserInfo storage from = userInfo[msg.sender][_from];
        UserInfo storage to = userInfo[msg.sender][_to];

        int256 _rewardDebt = int256((_amount * sett.accBadgerPerShare) / PRECISION);

        if (_from == address(0)) {
            // notifyDeposit
            to.amount += _amount;
            to.rewardDebt += _rewardDebt;

            settInfo[msg.sender].lpSupply += _amount;
            emit Deposit(_to, _pid, _amount);
        } else if (_to == address(0)) {
            // notifyWithdraw
            from.rewardDebt -= _rewardDebt;
            from.amount -= _amount;

            settInfo[msg.sender].lpSupply -= _amount;

            emit Withdraw(_from, _pid, _amount);
        } else {
            // transfer between users
            to.amount += _amount;
            from.amount -= _amount;

            to.rewardDebt += _rewardDebt;
            from.rewardDebt -= _rewardDebt;

            emit Transfer(_from, _to, _pid, _amount);
        }
    }

    /// @notice Harvest badger rewards for a vault sender to `to`
    /// @param _settAddress The address of the sett
    /// @param to Receiver of BADGER rewards
    function claim(address _settAddress, address to) public whenNotPaused {
        SettInfo memory sett = updateSett(_settAddress);
        UserInfo storage user = userInfo[_settAddress][msg.sender];
        int256 accumulatedBadger = int256((user.amount * sett.accBadgerPerShare) / PRECISION);
        uint256 _pendingBadger = uint256(accumulatedBadger - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedBadger;

        // Interactions
        if (_pendingBadger != 0) {
            BADGER.safeTransfer(to, _pendingBadger);
        }
        

        emit Harvest(msg.sender, _settAddress, _pendingBadger);
    }
}