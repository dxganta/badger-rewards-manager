from brownie import *
from brownie import (
    interface,
    FlashAttack
)
import brownie
from helpers.constants import *
from helpers.utils import *
from config import DAI, CRV


def test_deposit_withdraw_rewards(deployer, users, vaults, badger_tree, badger, want):

    dai = interface.IERC20(DAI)
    crv = interface.IERC20(CRV)
    vault = vaults[0]
    badger_tree.add(vault, [badger, DAI, CRV], {"from": deployer})
    attacker = users[2]

    want.approve(vault, MaxUint256, {"from": users[0]})
    want.approve(vault, MaxUint256, {"from": users[1]})
    toDeposit = want.balanceOf(users[0])

    vault.deposit(toDeposit * 0.000001, {"from": users[0]})

    # setup the flash attack contract
    flash_attack = FlashAttack.deploy(vault, {"from": attacker})

    blocks = 100
    badger_amount = 100 * 10**18
    dai_amount = 400 * 10**18
    crv_amount = 200 * 10**18
    badger.transfer(badger_tree, badger_amount, {"from": deployer})
    dai.transfer(badger_tree, dai_amount, {"from": deployer})
    crv.transfer(badger_tree, crv_amount, {"from": deployer})
    badger_tree.addSettRewards(
        vault, blocks, [badger_amount, dai_amount, crv_amount], {"from": deployer})

    chain.mine(int(blocks * 0.1))

    want.transfer(flash_attack, toDeposit * 0.5, {"from": attacker})
    # the settV3 currently has a check to disallow deposit by a smart contract
    # so that saves the flash attack problem anyway
    with brownie.reverts("Access denied for caller"):
        flash_attack.attack(want.balanceOf(flash_attack), want)
        # however, if this fails, comment out L44-L45, uncomment L48 & test again

    # flash_attack.attack(want.balanceOf(flash_attack), want)

    chain.mine(blocks)

    with brownie.reverts("No pending rewards"):
        badger_tree.claim(vault, flash_attack, [
                          0, 1, 2], {"from": flash_attack})
