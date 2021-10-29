from brownie import *
from brownie import (
    interface
)
from helpers.constants import *
from helpers.utils import *
from config import DAI, CRV

# not tests actually
# just a series of functions to get the gas costs for each method by using
# brownie test tests/test_gas_costs -s --gas


def test_gas_costs(deployer, users, vaults, badger_tree, badger, want):
    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[0]
    badger_tree.add(vault, [badger], {"from": deployer})

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    toDeposit = want.balanceOf(users[0])

    vault.deposit(toDeposit * 0.1, {"from": users[0]})
    vault.deposit(toDeposit * 0.2, {"from": users[1]})

    blocks = 10
    badger_amount = 1 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount], {"from": deployer})

    chain.mine(blocks)

    # gas for claiming 1 reward token
    for i in range(2):
        badger_tree.claim(vault, users[i], [0], {"from": users[i]})

    badger_tree.addRewardToken(vault, dai, {"from": deployer})

    blocks = 10
    badger_amount = 1 * 10**18
    dai_amount = 10 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount], {"from": deployer})

    chain.mine(blocks)

    # gas for claiming 2 reward tokens
    for i in range(2):
        badger_tree.claim(vault, users[i], [0, 1], {"from": users[i]})

    badger_tree.addRewardToken(vault, crv, {"from": deployer})

    blocks = 10
    badger_amount = 1 * 10**18
    dai_amount = 10 * 10**18
    crv_amount = 1 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(blocks)

    # gas for claiming 3 reward tokens
    for i in range(2):
        badger_tree.claim(vault, users[i], [0, 1, 2], {"from": users[i]})
