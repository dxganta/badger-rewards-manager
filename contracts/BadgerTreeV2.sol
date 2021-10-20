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

// TODO: update LpSupply to read balance from sett
// TODO: update userInfo amount to read shares from sett

// IDEA: instead of updating the accTokensPerShare for every reward token why not just update the accBadgersPerShare only
// like you are doing now & make the number of other reward tokens somehow a function of the accBadgerPerShare variable


// dont even need a badger_per_block
// just put some badgers give the duration (in seconds) till which you want these
// badgers to complete & the function will automatically calculate the badger_reward_per_block
// lpSupply is the total number of vault shares, and user's amount is the balanceOf shares he owns

contract BadgerTreeV2 is BoringBatchable, BoringOwnable, PausableUpgradeable  {
    using BoringERC20 for IERC20;

    /// @notice Info of each user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of BADGER that the user has withdrawn
    struct UserInfo {
        int256 rewardDebt;
    }

    /// @notice Info of each sett.
    struct SettInfo {
        uint64 lastRewardBlock; // the last block when the reward p were updated
        uint64 endingTimeStamp; // ending timestamp for current reward cycle
        uint128 accBadgerPerShare; // number of tokens accumulated per share till lastRewardBlock
        uint128 badgerPerBlock; // number of reward token per block 
        address[] rewardTokens;  // address of all the reward tokens
        uint256[] tokenToBadgerRatios; // ratio of total emitted token to total emitted badgers
    }

    /// @notice Address of BADGER contract.
    IERC20 public immutable BADGER;

    /// @notice Info of each sett. settAddress => settInfo
    mapping(address => SettInfo) public settInfo;

    /// @notice Info of each user that stakes Vault tokens. settAddress => userAddress => UserInfo
    mapping (address => mapping (address => UserInfo)) public userInfo;

    uint64 private constant PRECISION = 1e12;
    uint64 public BLOCK_TIME = 12; // block time in seconds

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, address indexed settAddress, uint256 amount);
    event LogSettAddition(address indexed settAddress, address[] rewardTokens);
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

    function add(address _settAddress, address[] memory _rewardTokens) public onlyOwner {
        uint256 lastRewardBlock = block.number;

        uint256[] memory _r = new uint256[](_rewardTokens.length);

        settInfo[_settAddress] = SettInfo({
            lastRewardBlock: uint64(lastRewardBlock),
            accBadgerPerShare: 0,
            endingTimeStamp: 0,
            badgerPerBlock: 0,
            rewardTokens: _rewardTokens,
            tokenToBadgerRatios: _r
        });

        emit LogSettAddition(_settAddress, _rewardTokens);
    }

    /// @notice add the sett rewards for the current cycle
    /// @param _settAddress address of the vault for which to add rewards
    /// @param _duration duration in seconds till when to use the given rewards
    /// @param _amounts array containing amount of each reward Token. _amounts[0] must be the badger amount. therefore _amounts.length = sett.rewardTokens.length + 1
    function addSettRewards(address _settAddress, uint64 _duration, uint256[] memory _amounts) public onlyOwner {
        SettInfo storage _sett = settInfo[_settAddress];
        require(block.timestamp > _sett.endingTimeStamp, "Rewards cycle not over");
        _sett.endingTimeStamp = uint64(block.timestamp) + _duration;
        _sett.badgerPerBlock = uint128(_amounts[0] / (_duration / BLOCK_TIME));

        // set the ratios for the rewardTokens of this sett for current cycle
        for (uint i = 1; i < _amounts.length; i++) {
            _sett.tokenToBadgerRatios[i-1] = (_sett.tokenToBadgerRatios[i-1] + ((_amounts[i] * PRECISION) / _amounts[0])) / 2;
        }
    }

    /// @notice View function to see all pending rewards on frontend.
    /// @param _sett The contract address of the sett
    /// @param _user Address of user.
    /// @return pending amount of all rewards. allPending[0] will be the badger rewards. rest will be the rewards for other tokens
    function pendingRewards(address _sett, address _user) external view returns (uint256[] memory) {
        SettInfo memory sett = settInfo[_sett];
        UserInfo storage user = userInfo[_sett][_user];
        uint256 accBadgerPerShare = sett.accBadgerPerShare;
        uint256 lpSupply = IERC20(_sett).totalSupply();
        uint256 userBal = IERC20(_sett).balanceOf(_user);
        if (block.number > sett.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number - sett.lastRewardBlock;
            uint256 badgerReward = blocks * sett.badgerPerBlock;
            accBadgerPerShare = accBadgerPerShare + ((badgerReward * PRECISION) / lpSupply);
        }
        uint256 pendingBadger = uint256(int256((userBal * accBadgerPerShare) / PRECISION) - user.rewardDebt);
        uint256[] memory allPending = new uint256[](sett.rewardTokens.length);
        allPending[0] = pendingBadger;
        for (uint i = 0; i < sett.rewardTokens.length; i ++) {
            allPending[i+1] = (sett.tokenToBadgerRatios[i] * pendingBadger) / PRECISION;
        }

        return allPending;
    }

    /// @notice Update reward variables of the given sett.
    /// @param _settAddress The address of the set
    /// @return sett Returns the sett that was updated.
    function updateSett(address _settAddress) public returns (SettInfo memory sett) {
        sett = settInfo[_settAddress];
        if (block.number > sett.lastRewardBlock && block.timestamp < sett.endingTimeStamp) {
            uint256 lpSupply = IERC20(_settAddress).totalSupply();
            if (lpSupply > 0) {
                uint256 blocks = block.number - sett.lastRewardBlock;
                uint256 badgerReward = blocks * sett.badgerPerBlock;
                sett.accBadgerPerShare += uint128((badgerReward * PRECISION) / lpSupply);
            }
            sett.lastRewardBlock = uint64(block.number);
            settInfo[_settAddress] = sett;
            emit LogUpdateSett(_settAddress, sett.lastRewardBlock, lpSupply, sett.accBadgerPerShare);
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
            to.rewardDebt += _rewardDebt;

            emit Deposit(_to, _pid, _amount);
        } else if (_to == address(0)) {
            // notifyWithdraw
            from.rewardDebt -= _rewardDebt;

            emit Withdraw(_from, _pid, _amount);
        } else {
            // transfer between users

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
        uint256 userBal = IERC20(_settAddress).balanceOf(msg.sender);
        int256 accumulatedBadger = int256((userBal * sett.accBadgerPerShare) / PRECISION);
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