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

contract BadgerTreeV2 is BoringBatchable, BoringOwnable, PausableUpgradeable  {
    using BoringERC20 for IERC20;

    /// @notice Info of each sett.
    struct SettInfo {
        uint64 lastRewardBlock; // the last block when the reward p were updated
        uint64 endingBlock; // ending timestamp for current reward cycle
        uint128 accBadgerPerShare; // number of tokens accumulated per share till lastRewardBlock
        uint128 badgerPerBlock; // number of reward token per block 
        address[] rewardTokens;  // address of all the reward tokens
        uint128[] totalTokens; // total number of emitted tokens till now. totalTokens[0] is for total emitted badgers. rest is for the other reward Tokens
    }

    /// @notice Address of BADGER contract.
    address public immutable BADGER;
    address public scheduler;
    address public pauser;

    /// @notice Info of each sett. settAddress => settInfo
    mapping(address => SettInfo) public settInfo;

    /// @notice rewardDebt of a user for a particular token in a sett. settAddress => userAddress => token => rewardDebt
    mapping (address => mapping (address => mapping (address => int128))) public rewardDebts;

    uint64 private constant PRECISION = 1e12;
    uint64 public BLOCK_TIME = 13; // block time in seconds

    event Deposit(address indexed user, address indexed sett, uint256 amount);
    event Withdraw(address indexed user, address indexed sett, uint256 amount);
    event Transfer(address indexed from, address indexed to, address indexed sett, uint256 amount);
    event Harvest(address indexed user, address indexed settAddress, uint256 amount);
    event LogSettAddition(address indexed settAddress, address[] rewardTokens);
    event LogSetSett(address indexed settAddress, uint256 allocPoint);
    event LogUpdateSett(address indexed settAddress, uint64 lastRewardBlock, uint256 lpSupply, uint256 accBadgerPerShare);

    /// @param _badger The BADGER token contract address.
    constructor(address _badger, address _scheduler, address _pauser) {
        BADGER = _badger;
        scheduler = _scheduler;
        pauser = _pauser;
    }

    /// @notice set the block time for the current blockchain
    function setBlockTime(uint64 _val) external onlyOwner {
        BLOCK_TIME = _val;
    }

    /// @notice set the scheduler who will schedule the rewards
    function setScheduler(address _scheduler) external {
        _onlyScheduler();
        scheduler = _scheduler;
    }

    /// @notice set the pauser who will pause the rewards
    function setPauser(address _pauser) external {
        _onlyPauser();
        pauser = _pauser;
    }

    function pause() external {
        _onlyPauser();
        _pause();
    }

    function unpause() external {
        _onlyPauser();
        _unpause();
    }

    /// @notice add a new sett to the rewards contract
    /// @param _settAddress contract address of the sett
    /// @param _rewardTokens array of the other reward tokens excluding BADGER
    function add(address _settAddress, address[] memory _rewardTokens) public onlyOwner {
        settInfo[_settAddress] = SettInfo({
            lastRewardBlock: 0,
            accBadgerPerShare: 0,
            endingBlock: 0,
            badgerPerBlock: 0,
            rewardTokens: _rewardTokens,
            totalTokens: new uint128[](_rewardTokens.length + 1)
        });

        emit LogSettAddition(_settAddress, _rewardTokens);
    }

    /// @notice add the sett rewards for the current cycle
    /// @param _settAddress address of the vault for which to add rewards
    /// @param _endingBlock ending block for current reward cycle
    /// @param _amounts array containing amount of each reward Token. _amounts[0] must be the badger amount. therefore _amounts.length = sett.rewardTokens.length + 1
    function addSettRewards(address _settAddress, uint64 _endingBlock, uint128[] memory _amounts) external {
        _onlyScheduler();
        updateSett(_settAddress);
        SettInfo storage _sett = settInfo[_settAddress];
        require(block.number > _sett.endingBlock, "Rewards cycle not over");
        _sett.endingBlock = _endingBlock;
        _sett.badgerPerBlock = uint128(_amounts[0] / (_endingBlock - block.number));

        // set the total rewardTokens of this sett for current cycle
        // this is used later to calculate the tokenToBadger Ratio for claiming rewards
        for (uint i = 0; i < _amounts.length; i++) {
            _sett.totalTokens[i] += _amounts[i];
        }
    }

    /// @notice View function to see all pending rewards on frontend.
    /// @param _sett The contract address of the sett
    /// @param _user Address of user.
    /// @return pending amount of all rewards. allPending[0] will be the badger rewards. rest will be the rewards for other tokens
    function pendingRewards(address _sett, address _user) external view returns (uint256[] memory) {
        SettInfo memory sett = settInfo[_sett];
        int128 rewardDebt = rewardDebts[_sett][_user][BADGER];
        uint256 accBadgerPerShare = sett.accBadgerPerShare;
        uint256 lpSupply = IERC20(_sett).totalSupply();
        uint256 userBal = IERC20(_sett).balanceOf(_user);
        if (block.number > sett.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number - sett.lastRewardBlock;
            uint256 badgerReward = blocks * sett.badgerPerBlock;
            accBadgerPerShare = accBadgerPerShare + ((badgerReward * PRECISION) / lpSupply);
        }
        int256 accumulatedBadger = int256((userBal * accBadgerPerShare) / PRECISION);
        uint256 pendingBadger = uint256( accumulatedBadger - rewardDebt);

        uint256[] memory allPending = new uint256[](sett.rewardTokens.length + 1);
        allPending[0] = pendingBadger;
        
        // calculate pendingTokens
        int128 accumulatedToken;
        for (uint i = 0; i < sett.rewardTokens.length; i ++) {
            // FORMULA: (TOKEN_TO_BADGER_RATIO * ACCUMULATED_BADGER) - USER_TOKEN_REWARD_DEBT
            accumulatedToken = (int128(sett.totalTokens[0] * PRECISION / sett.totalTokens[i+1]) * int128(accumulatedBadger)) / int64(PRECISION);
            allPending[i+1] = uint128(accumulatedToken - rewardDebts[_sett][msg.sender][sett.rewardTokens[i]]);
        }

        return allPending;
    }

    /// @notice Update reward variables of the given sett.
    /// @param _settAddress The address of the set
    /// @return sett Returns the sett that was updated.
    function updateSett(address _settAddress) public returns (SettInfo memory sett) {
        sett = settInfo[_settAddress];
        uint64 currBlock = uint64(block.number);
        if (block.number > sett.endingBlock) {
            // this will happen most probably when updateSett is called on addSettRewards
            currBlock = sett.endingBlock;
        }
        if (currBlock > sett.lastRewardBlock) {
            uint256 lpSupply = IERC20(_settAddress).totalSupply();
            if (lpSupply > 0) {
                uint256 blocks = currBlock - sett.lastRewardBlock;
                uint256 badgerReward = blocks * sett.badgerPerBlock;
                sett.accBadgerPerShare += uint128((badgerReward * PRECISION) / lpSupply);
            }
            sett.lastRewardBlock = currBlock;
            settInfo[_settAddress] = sett;
            emit LogUpdateSett(_settAddress, sett.lastRewardBlock, lpSupply, sett.accBadgerPerShare);
        }
    }

    // can be called only by vault
    function notifyTransfer(uint256 _amount, address _from, address _to) public {
        SettInfo memory sett = updateSett(msg.sender);

        int128 _rewardDebt = int128(int256((_amount * sett.accBadgerPerShare) / PRECISION));

        if (_from == address(0)) {
            // notifyDeposit
            rewardDebts[msg.sender][_to][BADGER] += _rewardDebt;

            emit Deposit(_to, msg.sender, _amount);
        } else if (_to == address(0)) {
            // notifyWithdraw
            rewardDebts[msg.sender][_from][BADGER] -= _rewardDebt;

            emit Withdraw(_from, msg.sender, _amount);
        } else {
            // transfer between users

            rewardDebts[msg.sender][_to][BADGER] += _rewardDebt;
            rewardDebts[msg.sender][_from][BADGER] -= _rewardDebt;

            emit Transfer(_from, _to, msg.sender, _amount);
        }
    }

    /// @notice Harvest badger rewards for a vault sender to `to`
    /// @param _settAddress The address of the sett
    /// @param to Receiver of BADGER rewards
    function claim(address _settAddress, address to) public whenNotPaused {
        SettInfo memory sett = updateSett(_settAddress);
        uint256 userBal = IERC20(_settAddress).balanceOf(msg.sender);
        int256 accumulatedBadger = int256((userBal * sett.accBadgerPerShare) / PRECISION);
        uint256 _pendingBadger = uint256(accumulatedBadger - rewardDebts[_settAddress][msg.sender][BADGER]);

        // add it to reward Debt
        rewardDebts[_settAddress][msg.sender][BADGER] = int128(accumulatedBadger);

        // Interactions
        if (_pendingBadger != 0) {
            IERC20(BADGER).safeTransfer(to, _pendingBadger);
        }

        // calculate pendingTokens
        int128 accumulatedToken;
        int128 pendingToken;
        for (uint i = 0; i < sett.rewardTokens.length; i ++) {
            // FORMULA: (TOKEN_TO_BADGER_RATIO * ACCUMULATED_BADGER) - USER_TOKEN_REWARD_DEBT
            accumulatedToken = (int128(sett.totalTokens[0] * PRECISION / sett.totalTokens[i+1]) * int128(accumulatedBadger)) / int64(PRECISION);
            pendingToken = accumulatedToken - rewardDebts[_settAddress][msg.sender][sett.rewardTokens[i]];
            rewardDebts[_settAddress][msg.sender][sett.rewardTokens[i]] += pendingToken;
            IERC20(sett.rewardTokens[i]).safeTransfer(to, uint128(pendingToken));
        }
        
        emit Harvest(msg.sender, _settAddress, _pendingBadger);
    }


    /// INTERNAL FUNCTIONS  
    function _onlyScheduler() internal view {
        require(msg.sender == scheduler, "Not Scheduler");
    }

    function _onlyPauser() internal view {
        require(msg.sender == pauser, "Not Pauser");
    }
}