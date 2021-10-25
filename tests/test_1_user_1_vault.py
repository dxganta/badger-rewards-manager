from brownie import *
from brownie import (
    interface
)
import brownie
from helpers.constants import *
from helpers.utils import *
from config import DAI, CRV


# def test_single_cycle(deployer, users, vaults, badger_tree, badger, want):
#     # test that vault can be added to the tree
#     dai = interface.IERC20(DAI)
#     crv = interface.IERC20(CRV)
#     vault = vaults[0]
#     user = users[0]
#     badger_tree.add(vault, [DAI, CRV], {"from": deployer})

#     # user must get added to pool rewards on deposit to vault
#     want.approve(vault, MaxUint256, {"from": user})
#     toDeposit = want.balanceOf(user)
#     vault.deposit(toDeposit, {"from": user})

#     # schedule sett rewards for 100 blocks
#     blocks = 100
#     badger_amount = 100 * 10**18
#     dai_amount = 400 * 10**18
#     crv_amount = 200 * 10**18
#     badger.transfer(badger_tree, badger_amount, {"from": deployer})
#     dai.transfer(badger_tree, dai_amount, {"from": deployer})
#     crv.transfer(badger_tree, crv_amount, {"from": deployer})
#     badger_tree.addSettRewards(
#         vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

#     # mine a little extra blocks to make sure no extra reward is given
#     # after cycle ends
#     chain.mine(blocks + 5)

#     actual_rewards = badger_tree.pendingRewards(vault, user)
#     actual_badger = actual_rewards[0]
#     actual_dai = actual_rewards[1]
#     actual_crv = actual_rewards[2]

#     assert approx(actual_badger, badger_amount, 0.001)
#     assert approx(actual_dai, dai_amount, 0.001)
#     assert approx(actual_crv, crv_amount, 0.001)

#     # g = web3.eth.estimate_gas(badger_tree.claim(vault, user, {"from": user}))
#     # print("Claim function gas estimate", g)
#     badger_tree.claim(vault, user, {"from": user})
#     assert approx(badger.balanceOf(user), badger_amount, 0.001)
#     assert approx(dai.balanceOf(user), dai_amount, 0.001)
#     assert approx(crv.balanceOf(user), crv_amount, 0.001)


def test_multi_cycles(deployer, users, vaults, badger_tree, badger, want):
    # test that vault can be added to the tree
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[1]
    user = users[1]
    badger_tree.add(vault, [DAI, CRV], {"from": deployer})

    # user must get added to pool rewards on deposit to vault
    want.approve(vault, MaxUint256, {"from": user})
    toDeposit = want.balanceOf(user)
    vault.deposit(toDeposit, {"from": user})

    # schedule sett rewards for 100 blocks 1st cycle
    blocks_1 = 100
    badger_amount_1 = 10 * 10**18
    dai_amount_1 = 40 * 10**18
    crv_amount_1 = 20 * 10**18
    badger.transfer(badger_tree, badger_amount_1, {"from": deployer})
    dai.transfer(badger_tree, dai_amount_1, {"from": deployer})
    crv.transfer(badger_tree, crv_amount_1, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks_1, [badger_amount_1, dai_amount_1, crv_amount_1], {"from": deployer})

    # schedule sett rewards for 70 blocks second cycle
    blocks_2 = 70
    badger_amount_2 = 5 * 10**18
    dai_amount_2 = 15 * 10**18
    crv_amount_2 = 10 * 10**18
    badger.transfer(badger_tree, badger_amount_2, {"from": deployer})
    dai.transfer(badger_tree, dai_amount_2, {"from": deployer})
    crv.transfer(badger_tree, crv_amount_2, {"from": deployer})
    with brownie.reverts("Rewards cycle not over"):
        badger_tree.addSettRewards(
            vault, blocks_2, [badger_amount_2, dai_amount_2, crv_amount_2], {"from": deployer})

    chain.mine(blocks_1)

    badger_tree.addSettRewards(
        vault, blocks_2, [badger_amount_2, dai_amount_2, crv_amount_2], {"from": deployer})

    chain.mine(blocks_2 + 10)

    actual_rewards = badger_tree.pendingRewards(vault, user)
    actual_badger = actual_rewards[0]
    actual_dai = actual_rewards[1]
    actual_crv = actual_rewards[2]

    assert approx(actual_badger, int(badger_amount_1) +
                  int(badger_amount_2), 0.001)
    assert approx(actual_dai, int(dai_amount_1) + int(dai_amount_2), 0.001)
    assert approx(actual_crv, int(crv_amount_1) + int(crv_amount_2), 0.001)

    badger_tree.claim(vault, user, {"from": user})

    assert approx(badger.balanceOf(user), int(badger_amount_1) +
                  int(badger_amount_2), 0.001)
    assert approx(dai.balanceOf(user), int(
        dai_amount_1) + int(dai_amount_2), 0.001)
    assert approx(crv.balanceOf(user), int(
        crv_amount_1) + int(crv_amount_2), 0.001)

    # schedule sett rewards for 50 blocks 3rd cycle
    blocks_3 = 50
    badger_amount_3 = 10 * 10**18
    dai_amount_3 = 40 * 10**18
    crv_amount_3 = 20 * 10**18
    badger.transfer(badger_tree, badger_amount_3, {"from": deployer})
    dai.transfer(badger_tree, dai_amount_3, {"from": deployer})
    crv.transfer(badger_tree, crv_amount_3, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks_3, [badger_amount_3, dai_amount_3, crv_amount_3], {"from": deployer})

    chain.mine(blocks_3)

    actual_rewards = badger_tree.pendingRewards(vault, user)
    actual_badger = actual_rewards[0]
    actual_dai = actual_rewards[1]
    actual_crv = actual_rewards[2]

    assert approx(actual_badger, badger_amount_3, 0.001)
    assert approx(actual_dai, dai_amount_3, 0.001)
    assert approx(actual_crv, crv_amount_3, 0.001)

    badger_tree.claim(vault, user, {"from": user})

    actual_rewards = badger_tree.pendingRewards(vault, user)
    assert actual_rewards[0] == 0
    assert actual_rewards[1] == 0
    assert actual_rewards[2] == 0


def test_multi_deposit_addSettRewards(deployer, users, vaults, badger_tree, badger, want):
    pass
