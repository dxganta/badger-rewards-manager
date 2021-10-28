from brownie import *
from brownie import (
    interface
)
from helpers.constants import *
from config import DAI, CRV
from pytest import approx


def test_transfer_flow(deployer, users, vaults, badger_tree, badger, want):
    # test that vault can be added to the tree
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[0]
    badger_tree.add(vault, [badger, DAI, CRV], {"from": deployer})

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    want.approve(vault, MaxUint256, {"from": users[2]})
    toDeposit = want.balanceOf(users[0])

    vault.deposit(toDeposit * 0.5, {"from": users[0]})

    # user 1 transfers 50% of his shares to user2
    vault.transfer(users[1], vault.balanceOf(
        users[0]) * 0.5, {"from": users[0]})

    # schedule sett rewards for 100 blocks
    blocks = 100
    badger_amount = 10 * 10**18
    dai_amount = 400 * 10**18
    crv_amount = 20 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks)

    pd1 = badger_tree.pendingRewards(vault, users[0])
    pd2 = badger_tree.pendingRewards(vault, users[1])

    # user 1 must get only 50% of the vault rewards & the rest must go to user 2
    assert approx(pd1[0]) == badger_amount * 0.5
    assert approx(pd2[0]) == badger_amount * 0.5

    assert approx(pd1[1]) == dai_amount * 0.5
    assert approx(pd2[1]) == dai_amount * 0.5

    assert approx(pd1[2]) == crv_amount * 0.5
    assert approx(pd2[2]) == crv_amount * 0.5

    for i in range(0, 2):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})

    # transferring in the middle of a cycle

    # schedule sett rewards for 100 blocks
    blocks = 50
    badger_amount = 10 * 10**18
    dai_amount = 300 * 10**18
    crv_amount = 70 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    u2_prcnt = vault.balanceOf(users[1]) / vault.totalSupply()
    u3_prcnt = vault.balanceOf(users[2]) / vault.totalSupply()

    chain.mine(int(blocks * 0.5))

    # from user2 to user3
    vault.transfer(users[2], vault.balanceOf(
        users[1]) * 0.5, {"from": users[1]})

    u2_prcnt_new = vault.balanceOf(users[1]) / vault.totalSupply()
    u3_prcnt_new = vault.balanceOf(users[2]) / vault.totalSupply()

    chain.mine(int(blocks * 0.5))

    pd2 = badger_tree.pendingRewards(vault, users[1])
    pd3 = badger_tree.pendingRewards(vault, users[2])

    assert approx(pd2[0]) == (badger_amount * u2_prcnt * 0.5) + (badger_amount * u2_prcnt_new *
                                                                 0.5) + (badger_amount/blocks * u2_prcnt) - \
        (badger_amount/blocks * u2_prcnt_new)
    assert approx(pd3[0]) == (badger_amount * u3_prcnt_new *
                              0.5) - (badger_amount/blocks * u3_prcnt_new)
