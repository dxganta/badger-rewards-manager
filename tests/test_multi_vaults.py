from brownie import *
from brownie import (
    interface
)
from helpers.constants import *
from config import DAI, CRV
from pytest import approx


def test_multi_vaults(deployer, users, vaults, badger_tree, badger, badger_whale, dai_whale, crv_whale, want):
    def addSettCycle(vault, blocks, badger_amount, dai_amount, crv_amount):
        badger.transfer(badger_tree, badger_amount, {"from": badger_whale})
        dai.transfer(badger_tree, dai_amount, {"from": dai_whale})
        crv.transfer(badger_tree, crv_amount, {"from": crv_whale})
        badger_tree.addSettRewards(
            vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    # test that vault can be added to the tree
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    badger_tree.add(vaults[0], [badger, DAI, CRV], {"from": deployer})
    badger_tree.add(vaults[1], [badger, DAI, CRV], {"from": deployer})

    for i in range(2):
        for j in range(4):
            want.approve(vaults[i], MaxUint256, {"from": users[j]})

    toDeposit = want.balanceOf(users[0])

    # multi sett deposit by user 1 & user 2
    vaults[0].deposit(toDeposit * 0.1, {"from": users[0]})
    vaults[0].deposit(toDeposit * 0.1, {"from": users[1]})

    vaults[1].deposit(toDeposit * 0.05, {"from": users[0]})
    vaults[1].deposit(toDeposit * 0.15, {"from": users[1]})

    v1_u1_prcnt = vaults[0].balanceOf(users[0]) / vaults[0].totalSupply()
    v1_u2_prcnt = vaults[0].balanceOf(users[1]) / vaults[0].totalSupply()
    v2_u1_prcnt = vaults[1].balanceOf(users[0]) / vaults[1].totalSupply()
    v2_u2_prcnt = vaults[1].balanceOf(users[1]) / vaults[1].totalSupply()

    assert approx(v1_u1_prcnt) == 0.1 / (0.1 + 0.1)
    assert approx(v1_u2_prcnt) == 0.1 / (0.1 + 0.1)
    assert approx(v2_u1_prcnt) == 0.05 / (0.05 + 0.15)
    assert approx(v2_u2_prcnt) == 0.15 / (0.05 + 0.15)

    # schedule sett rewards for both vaults
    blocks_1 = 100
    badger_amount_1 = 100 * 10**18
    dai_amount_1 = 400 * 10**18
    crv_amount_1 = 200 * 10**18
    addSettCycle(vaults[0], blocks_1, badger_amount_1,
                 dai_amount_1, crv_amount_1)

    blocks_2 = 120
    badger_amount_2 = 80 * 10**18
    dai_amount_2 = 1000 * 10**18
    crv_amount_2 = 150 * 10**18
    addSettCycle(vaults[1], blocks_2, badger_amount_2,
                 dai_amount_2, crv_amount_2)

    chain.mine(blocks_2)

    pd11 = badger_tree.pendingRewards(vaults[0], users[0])
    pd12 = badger_tree.pendingRewards(vaults[0], users[1])
    pd21 = badger_tree.pendingRewards(vaults[1], users[0])
    pd22 = badger_tree.pendingRewards(vaults[1], users[1])

    assert approx(pd11[0] + pd21[0]) == v1_u1_prcnt * \
        badger_amount_1 + v2_u1_prcnt * badger_amount_2

    assert approx(pd12[0] + pd22[0]) == v1_u2_prcnt * \
        badger_amount_1 + v2_u2_prcnt * badger_amount_2

    assert approx(pd11[1] + pd21[1]) == v1_u1_prcnt * \
        dai_amount_1 + v2_u1_prcnt * dai_amount_2

    assert approx(pd12[1] + pd22[1]) == v1_u2_prcnt * \
        dai_amount_1 + v2_u2_prcnt * dai_amount_2

    assert approx(pd11[2] + pd21[2]) == v1_u1_prcnt * \
        crv_amount_1 + v2_u1_prcnt * crv_amount_2

    assert approx(pd12[2] + pd22[2]) == v1_u2_prcnt * \
        crv_amount_1 + v2_u2_prcnt * crv_amount_2

    # for i in range(2):
    #     for j in range(2):
    #         badger_tree.claim(vaults[i], users[j], [
    #                           0, 1, 2], {"from": users[j]})

    badger_tree.claim(vaults[0], users[0], [0, 1, 2], {"from": users[0]})
    badger_tree.claim(vaults[0], users[1], [0, 1, 2], {"from": users[1]})
    badger_tree.claim(vaults[1], users[0], [0, 1, 2], {"from": users[0]})
    badger_tree.claim(vaults[1], users[1], [0, 1, 2], {"from": users[1]})

    print(f"Badger balance {badger.balanceOf(badger_tree)}")
    print(f"DAI Balance {dai.balanceOf(badger_tree)}")
    print(f"CRV Balance {crv.balanceOf(badger_tree)}")
