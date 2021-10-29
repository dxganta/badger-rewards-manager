from brownie import *
from brownie import (
    interface
)
import brownie
from helpers.constants import *
from helpers.utils import *
from config import DAI, CRV


def test_permissions(deployer, users, vaults, badger_tree, badger, want):

    pauser = deployer
    scheduler = deployer
    owner = deployer

    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[0]
    with brownie.reverts():
        badger_tree.add(vault, [badger, DAI, CRV], {"from": users[2]})

    badger_tree.add(vault, [badger, DAI, CRV], {"from": owner})

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    toDeposit = want.balanceOf(users[0])

    vault.deposit(toDeposit * 0.001, {"from": users[0]})

    blocks = 100
    badger_amount = 1 * 10**18
    dai_amount = 4 * 10**18
    crv_amount = 2 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    with brownie.reverts("Not Scheduler"):
        badger_tree.addSettRewards(
            vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": users[2]})

    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": scheduler})

    chain.mine(int(blocks * 0.5))

    with brownie.reverts("Not Pauser"):
        badger_tree.pause({"from": users[1]})

    badger_tree.pause({"from": pauser})

    with brownie.reverts("Pausable: paused"):
        badger_tree.claim(vault, users[0], [0, 1, 2], {"from": users[0]})

    with brownie.reverts("Not Pauser"):
        badger_tree.unpause({"from": users[1]})

    badger_tree.unpause({"from": pauser})

    tx = badger_tree.claim(vault, users[0], [0, 1, 2], {"from": users[0]})

    assert tx.events['Claimed'][0]['amount'] > 0
