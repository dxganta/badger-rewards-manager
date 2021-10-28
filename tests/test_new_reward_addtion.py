from brownie import *
from brownie import (
    interface
)
import brownie
from helpers.constants import *
from config import DAI, CRV, LINK
from pytest import approx


def test_new_reward_addition(deployer, users, vaults, badger_tree, badger, want):
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    link = interface.IERC20(LINK)
    vault = vaults[0]
    badger_tree.add(vault, [badger, DAI], {"from": deployer})

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    toDeposit = want.balanceOf(users[0])

    vault.deposit(toDeposit * 0.1, {"from": users[0]})
    vault.deposit(toDeposit * 0.2, {"from": users[1]})

    u1_prcnt = vault.balanceOf(users[0]) / vault.totalSupply()
    u2_prcnt = vault.balanceOf(users[1]) / vault.totalSupply()

    # simple first cyle
    blocks = 50
    badger_amount = 10 * 10**18
    dai_amount = 400 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount], {"from": deployer})

    chain.mine(blocks)

    for i in range(2):
        badger_tree.claim(vault, users[i], [0, 1], {"from": users[i]})

    # add a new reward token for the second cycle
    badger_tree.addRewardToken(vault, crv, {"from": deployer})

    blocks = 100
    badger_amount = 10 * 10**18
    dai_amount = 400 * 10**18
    crv_amount = 10 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(int(blocks * 0.5))

    with brownie.reverts("Rewards cycle not over"):
        badger_tree.addRewardToken(vault, link)

    chain.mine(int(blocks * 0.5))

    pd1 = badger_tree.pendingRewards(vault, users[0])
    pd2 = badger_tree.pendingRewards(vault, users[1])

    assert approx(pd1[2]) == crv_amount * u1_prcnt
    assert approx(pd2[2]) == crv_amount * u2_prcnt
    assert approx(crv_amount) == pd1[2] + pd2[2]
