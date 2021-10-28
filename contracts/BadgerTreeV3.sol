// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/BoringBatchable.sol";
import "../interfaces/BoringOwnable.sol";
import "../interfaces/token/IERC20.sol";
import "./interfaces/ISettV3.sol";
import "../libraries/BoringERC20.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// DIFFERENT RATES OF EMISSIONS PER BLOCK PER SETT

// NOTE: when adding a vault for the first time, if its lpSupply is zero but badgerPerBlock > 0, there are badgers lost till the lpSupply > 0

contract BadgerTreeV3 is BoringBatchable, BoringOwnable, PausableUpgradeable {
    using BoringERC20 for IERC20;

    /// @notice Info of each sett.
    struct SettInfo {
        uint64 lastRewardBlock; // the last block when the reward p were updated
        uint64 endingBlock; // ending timestamp for current reward cycle
        uint128[] accTokenPerShare; // number of tokens accumulated per share till lastRewardBlock
        uint128[] tokenPerBlock; // number of reward token per block
        address[] rewardTokens; // address of all the reward tokens
    }

    address public scheduler;
    address public pauser;

    /// @notice Info of each sett. settAddress => settInfo
    mapping(address => SettInfo) public settInfo;

    /// @notice rewardDebt of a user for a particular token in a sett. settAddress => userAddress => token => rewardDebt
    mapping(address => mapping(address => mapping(address => int256)))
        public rewardDebts;

    uint64 private constant PRECISION = 1e12;

    event Deposit(address indexed user, address indexed sett, uint256 amount);
    event Withdraw(address indexed user, address indexed sett, uint256 amount);
    event Transfer(
        address indexed from,
        address indexed to,
        address indexed sett,
        uint256 amount
    );
    event Claimed(
        address indexed user,
        address indexed token,
        address indexed sett,
        uint256 amount,
        uint256 timestamp,
        uint256 blockNumber
    );
    event SettAddition(address indexed settAddress, address[] rewardTokens);
    event RewardTokenAddition(address indexed settAddress, address reward);
    event NewRewardsCycle(
        address indexed settAddress,
        uint256 startBlock,
        uint256 endBlock,
        address[] rewards,
        uint128[] amounts
    );
    event UpdateSett(
        address indexed settAddress,
        uint64 lastRewardBlock,
        uint256 lpSupply,
        uint128[] accTokenPerShare
    );

    constructor(address _scheduler, address _pauser) {
        scheduler = _scheduler;
        pauser = _pauser;
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
    function add(address _settAddress, address[] memory _rewardTokens)
        public
        onlyOwner
    {
        settInfo[_settAddress] = SettInfo({
            lastRewardBlock: 0,
            accTokenPerShare: new uint128[](_rewardTokens.length),
            tokenPerBlock: new uint128[](_rewardTokens.length),
            endingBlock: 0,
            rewardTokens: _rewardTokens
        });

        emit SettAddition(_settAddress, _rewardTokens);
    }

    /// @notice add a new reward token to a particular sett
    /// @param _settAddress address of the sett for which to add a new reward token
    /// @param _reward address of the reward token to add
    function addRewardToken(address _settAddress, address _reward) public onlyOwner {
        SettInfo storage sett = settInfo[_settAddress];
        _cycleNotOver(sett.endingBlock);
        sett.rewardTokens.push(_reward);
        sett.accTokenPerShare.push(0);
        sett.tokenPerBlock.push(0);

        emit RewardTokenAddition(_settAddress, _reward);
    }

    /// @notice add the sett rewards for the current cycle
    /// @param _settAddress address of the vault for which to add rewards
    /// @param _blocks number of blocks for which this cycle should last
    /// @param _amounts array containing amount of each reward Token. _amounts[0] must be the badger amount. therefore _amounts.length = sett.rewardTokens.length + 1
    function addSettRewards(
        address _settAddress,
        uint64 _blocks,
        uint128[] memory _amounts
    ) external {
        _onlyScheduler();
        updateSett(_settAddress);
        SettInfo storage sett = settInfo[_settAddress];
        _cycleNotOver(sett.endingBlock);
        sett.lastRewardBlock = uint64(block.number);
        sett.endingBlock = sett.lastRewardBlock + _blocks;
        // set the total rewardTokens of this sett for current cycle
        // this is used later to calculate the tokenToBadger Ratio for claiming rewards
        for (uint256 i = 0; i < _amounts.length; i++) {
            sett.tokenPerBlock[i] = uint128(_amounts[i] / _blocks);
        }

        emit NewRewardsCycle(
            _settAddress,
            block.number,
            sett.endingBlock,
            sett.rewardTokens,
            _amounts
        );
    }

    /// @notice View function to see all pending rewards on frontend.
    /// @param _settAddress The contract address of the sett
    /// @param _user Address of user.
    /// @return pending amount of all rewards. allPending[0] will be the badger rewards. rest will be the rewards for other tokens
    function pendingRewards(address _settAddress, address _user)
        external
        view
        returns (uint256[] memory)
    {
        SettInfo memory sett = settInfo[_settAddress];
        uint256 n = sett.rewardTokens.length;
        uint256[] memory allPending = new uint256[](n);

        uint64 currBlock = uint64(block.number);
        if (block.number > sett.endingBlock) {
            // this will happen most probably when updateSett is called on addSettRewards
            currBlock = sett.endingBlock;
        }

        uint256 blocks = currBlock - sett.lastRewardBlock;
        uint256 lpSupply = IERC20(_settAddress).totalSupply();
        uint256 userBal = IERC20(_settAddress).balanceOf(_user);

        for (uint256 i = 0; i < n; i++) {
            int256 rewardDebt = rewardDebts[_settAddress][_user][
                sett.rewardTokens[i]
            ];
            uint256 accTokenPerShare = sett.accTokenPerShare[i];
            if (currBlock > sett.lastRewardBlock && lpSupply != 0) {
                uint256 tokenReward = blocks * sett.tokenPerBlock[i];
                accTokenPerShare =
                    accTokenPerShare +
                    ((tokenReward * PRECISION) / lpSupply);
            }
            int256 accumulatedToken = int256(
                (userBal * accTokenPerShare) / PRECISION
            );
            uint256 pendingToken = uint256(accumulatedToken - rewardDebt);

            allPending[i] = pendingToken;
        }

        return allPending;
    }

    /// @notice Update reward variables of the given sett.
    /// @param _settAddress The address of the set
    /// @return sett Returns the sett that was updated.
    function updateSett(address _settAddress)
        public
        returns (SettInfo memory sett)
    {
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
                for (uint256 i = 0; i < sett.rewardTokens.length; i++) {
                    uint256 tokenReward = blocks * sett.tokenPerBlock[i];
                    sett.accTokenPerShare[i] += uint128(
                        (tokenReward * PRECISION) / lpSupply
                    );
                }
            }
            sett.lastRewardBlock = currBlock;
            settInfo[_settAddress] = sett;
            emit UpdateSett(
                _settAddress,
                sett.lastRewardBlock,
                lpSupply,
                sett.accTokenPerShare
            );
        }
    }

    // should be called only by vault
    // well can be called by anyone tbh but doesn't make sense if anybody else calls it
    function notifyTransfer(
        uint256 _amount,
        address _from,
        address _to
    ) public {
        SettInfo memory sett = settInfo[msg.sender];

        uint256 t = sett.rewardTokens.length;
        int128[] memory tokenDebts = new int128[](t);

        for (uint256 i = 0; i < t; i++) {
            tokenDebts[i] = int128(
                int256((_amount * sett.accTokenPerShare[i]) / PRECISION)
            );
        }

        if (_from == address(0)) {
            // notifyDeposit
            for (uint256 i = 0; i < t; i++) {
                rewardDebts[msg.sender][_to][
                    sett.rewardTokens[i]
                ] += tokenDebts[i];
            }

            emit Deposit(_to, msg.sender, _amount);
        } else if (_to == address(0)) {
            // notifyWithdraw
            for (uint256 i = 0; i < t; i++) {
                rewardDebts[msg.sender][_from][
                    sett.rewardTokens[i]
                ] -= tokenDebts[i];
            }

            emit Withdraw(_from, msg.sender, _amount);
        } else {
            // transfer between users
            for (uint256 i = 0; i < t; i++) {
                rewardDebts[msg.sender][_to][
                    sett.rewardTokens[i]
                ] += tokenDebts[i];
                rewardDebts[msg.sender][_from][
                    sett.rewardTokens[i]
                ] -= tokenDebts[i];
            }

            emit Transfer(_from, _to, msg.sender, _amount);
        }
    }

    /// @notice Harvest badger rewards for a vault sender to `to`
    /// @param _settAddress The address of the sett
    /// @param _to Receiver of BADGER rewards
    /// @param _rewardIndexes addresses of the reward tokens to claim
    function claim(
        address _settAddress,
        address _to,
        uint256[] memory _rewardIndexes
    ) public whenNotPaused {
        SettInfo memory sett = updateSett(_settAddress);
        uint256 userBal = IERC20(_settAddress).balanceOf(msg.sender);

        address reward;
        for (uint256 j = 0; j < _rewardIndexes.length; j++) {
            reward = sett.rewardTokens[_rewardIndexes[j]];
            int256 accumulatedToken = int256(
                (userBal * sett.accTokenPerShare[_rewardIndexes[j]]) / PRECISION
            );
            uint256 pendingToken = uint256(
                accumulatedToken - rewardDebts[_settAddress][msg.sender][reward]
            );

            // add it to reward Debt
            rewardDebts[_settAddress][msg.sender][reward] = accumulatedToken;

            // Interactions
            require(pendingToken != 0, "No pending rewards");
            IERC20(reward).safeTransfer(_to, pendingToken);

            emit Claimed(
                _to,
                reward,
                _settAddress,
                pendingToken,
                block.timestamp,
                block.number
            );
        }
    }

    /// INTERNAL FUNCTIONS
    function _onlyScheduler() internal view {
        require(msg.sender == scheduler, "Not Scheduler");
    }

    function _onlyPauser() internal view {
        require(msg.sender == pauser, "Not Pauser");
    }

    function _cycleNotOver(uint64 _endingBlock) internal view {
        require(block.number > _endingBlock, "Rewards cycle not over");
    }
}
