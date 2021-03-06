from brownie import *
from brownie import (
    interface
)
from helpers.constants import *
from helpers.utils import *
from config import DAI, CRV


def test_deposit_withdraw_rewards(deployer, users, vaults, badger_tree, badger, want):
    # test that vault can be added to the tree
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[0]
    badger_tree.add(vault, [badger, DAI, CRV], {"from": deployer})

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    want.approve(vault, MaxUint256, {"from": users[2]})
    toDeposit = want.balanceOf(users[0])

    # 70% 30%
    vault.deposit(toDeposit * 0.7, {"from": users[0]})
    vault.deposit(toDeposit * 0.3, {"from": users[1]})

    # schedule sett rewards for 100 blocks
    blocks = 100
    badger_amount = 10 * 10**18
    dai_amount = 40 * 10**18
    crv_amount = 20 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks + 1)

    # test that user1 is getting 70% rewards & user2 is getting 30%

    pd1 = badger_tree.pendingRewards(vault, users[0])
    pd2 = badger_tree.pendingRewards(vault, users[1])

    assert approx(pd1[0], badger_amount * 0.7, 0.001)
    assert approx(pd2[0], badger_amount * 0.3, 0.001)

    assert approx(pd1[1], dai_amount * 0.7, 0.001)
    assert approx(pd2[1], dai_amount * 0.3, 0.001)

    assert approx(pd1[2], crv_amount * 0.7, 0.001)
    assert approx(pd2[2], crv_amount * 0.3, 0.001)

    for i in range(0, 2):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})

    # user1 withdraws 50% of his deposit
    # & user2 deposits 50% more

    vault.withdraw(toDeposit * 0.7 * 0.5, {"from": users[0]})
    vault.deposit(toDeposit * 0.3, {"from": users[1]})

    u1_prcnt = vault.balanceOf(users[0]) / vault.totalSupply()
    u2_prcnt = vault.balanceOf(users[1]) / vault.totalSupply()

    # 2nd cycle
    blocks = 100
    badger_amount = 5 * 10**18
    dai_amount = 90 * 10**18
    crv_amount = 10 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks+1)

    pd1 = badger_tree.pendingRewards(vault, users[0])
    pd2 = badger_tree.pendingRewards(vault, users[1])

    assert approx(pd1[0], badger_amount * u1_prcnt, 0.001)
    assert approx(pd2[0], badger_amount * u2_prcnt, 0.001)

    assert approx(pd1[1], dai_amount * u1_prcnt, 0.001)
    assert approx(pd2[1], dai_amount * u2_prcnt, 0.001)

    assert approx(pd1[2], crv_amount * u1_prcnt, 0.001)
    assert approx(pd2[2], crv_amount * u2_prcnt, 0.001)

    for i in range(0, 2):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})

    # 3rd cycle => depositing in the middle of a cycle
    blocks = 100
    badger_amount = 2 * 10**18
    dai_amount = 100 * 10**18
    crv_amount = 5 * 10**18
    # adding a very very very little extra tokens to make sure we dont have any precision errors
    badger.transfer(badger_tree, badger_amount + 5, {"from": deployer})
    dai.transfer(badger_tree, dai_amount + 5, {"from": deployer})
    crv.transfer(badger_tree, crv_amount + 5, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(int(blocks * 0.4))

    vault.deposit(toDeposit * 0.1, {"from": users[0]})

    u1_prcnt_new = vault.balanceOf(users[0]) / vault.totalSupply()
    u2_prcnt_new = vault.balanceOf(users[1]) / vault.totalSupply()

    chain.mine(int(blocks*0.6) + 2)

    pd1b = badger_tree.pendingRewards(vault, users[0])
    pd2b = badger_tree.pendingRewards(vault, users[1])

    # u1_prct for first 40% blocks & u1_prcnt_new for next 60% blocks, minus the one block where he deposits where he will still get the u1_prcnt rewards
    assert approx(pd1b[0], (badger_amount * 0.4 * u1_prcnt) +
                  (badger_amount * 0.6 * u1_prcnt_new) - (badger_amount/blocks * u1_prcnt_new) + (badger_amount/blocks * u1_prcnt), 0.001)
    assert approx(pd2b[0], (badger_amount * 0.4 * u2_prcnt) +
                  (badger_amount * 0.6 * u2_prcnt_new) - (badger_amount/blocks * u2_prcnt_new) + (badger_amount/blocks * u2_prcnt), 0.001)

    assert approx(pd1b[1], (dai_amount * 0.4 * u1_prcnt) +
                  (dai_amount * 0.6 * u1_prcnt_new) - (dai_amount/blocks * u1_prcnt_new) + (dai_amount/blocks * u1_prcnt), 0.001)
    assert approx(pd2b[1], (dai_amount * 0.4 * u2_prcnt) +
                  (dai_amount * 0.6 * u2_prcnt_new) - (dai_amount/blocks * u2_prcnt_new) + (dai_amount/blocks * u2_prcnt), 0.001)

    assert approx(pd1b[2], (crv_amount * 0.4 * u1_prcnt) +
                  (crv_amount * 0.6 * u1_prcnt_new) - (crv_amount/blocks * u1_prcnt_new) + (crv_amount/blocks * u1_prcnt), 0.001)
    assert approx(pd2b[2], (crv_amount * 0.4 * u2_prcnt) +
                  (crv_amount * 0.6 * u2_prcnt_new) - (crv_amount/blocks * u2_prcnt_new) + (crv_amount/blocks * u2_prcnt), 0.001)

    for i in range(0, 2):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})

    # testing the transfer of tokens
    # transfer 30% shares of user1 to user3
    vault.transfer(
        users[2],  0.3 * vault.balanceOf(users[0]), {"from": users[0]})

    # now for the third cycle user1 must get 70% of his previous share & the user3 must get the rest 30%
    # 4th cycle
    blocks = 50
    badger_amount = 30 * 10**18
    dai_amount = 150 * 10**18
    crv_amount = 40 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks)

    pd1 = badger_tree.pendingRewards(vault, users[0])
    pd2 = badger_tree.pendingRewards(vault, users[1])
    pd3 = badger_tree.pendingRewards(vault, users[2])

    assert approx(pd1[0], badger_amount * 0.7 * u1_prcnt_new, 0.001)
    assert approx(pd2[0], badger_amount * u2_prcnt_new, 0.001)
    assert approx(pd3[0], badger_amount * 0.3 * u1_prcnt_new, 0.001)

    assert approx(pd1[1], dai_amount * 0.7 * u1_prcnt_new, 0.001)
    assert approx(pd2[1], dai_amount * u2_prcnt_new, 0.001)
    assert approx(pd3[1], dai_amount * 0.3 * u1_prcnt_new, 0.001)

    assert approx(pd1[2], crv_amount * 0.7 * u1_prcnt_new, 0.001)
    assert approx(pd2[2], crv_amount * u2_prcnt_new, 0.001)
    assert approx(pd3[2], crv_amount * 0.3 * u1_prcnt_new, 0.001)

    for i in range(0, 3):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})

    # final withdraw tests
    # user3 withdraws everything & stops getting rewards
    vault.withdrawAll({"from": users[2]})
    blocks = 50
    badger_amount = 1 * 10**18
    dai_amount = 10 * 10**18
    crv_amount = 1 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks)

    pd3 = badger_tree.pendingRewards(vault, users[2])

    assert pd3 == (0, 0, 0)
