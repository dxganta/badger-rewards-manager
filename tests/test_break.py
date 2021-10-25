from helpers.constants import *
from brownie import Wei, chain
import brownie

MINE_BLOCK_TEST = 100


def test_break(
    deployer, vaults, badger_tree, want_whale, badger_whale, want, badger, accounts
):
    want.approve(vaults[0], MaxUint256, {"from": want_whale})

    badger_tree.add(vaults[0], [], {"from": deployer})

    # accounts[0] is _scheduler & _pauser, 7200 blocks
    badger_emitted = 100
    badger.transfer(badger_tree, Wei(
        f"{badger_emitted} ether"), {"from": badger_whale})
    badger_tree.addSettRewards(
        vaults[0], 7200, [Wei(f"{badger_emitted} ether")], {
            "from": accounts[0]}
    )

    # user 1st deposit
    vaults[0].deposit(want.balanceOf(want_whale) * 0.05, {"from": want_whale})

    chain.mine(MINE_BLOCK_TEST)

    reward_pending_before = badger_tree.pendingRewards(vaults[0], want_whale)[
        0]

    # same user 2nd deposit
    vaults[0].deposit(want.balanceOf(want_whale) * 0.05, {"from": want_whale})

    reward_pending_after = badger_tree.pendingRewards(vaults[0], want_whale)[0]

    # should be higher badger rewards, right? TOFIX!
    assert reward_pending_after > reward_pending_before

    tx = badger_tree.claim(vaults[0], want_whale, {"from": want_whale})

    assert tx.events["Harvest"]["amount"] == badger.balanceOf(want_whale)
    assert tx.events["Harvest"]["amount"] > reward_pending_after

    chain.mine(MINE_BLOCK_TEST)

    vaults[0].withdrawAll({"from": want_whale})

    assert vaults[0].balanceOf(want_whale) == 0

    reward_after_withdraw = badger_tree.pendingRewards(vaults[0], want_whale)[
        0]

    tx_after_withdrawal = badger_tree.claim(
        vaults[0], want_whale, {"from": want_whale})

    assert tx_after_withdrawal.events["Harvest"]["amount"] == reward_after_withdraw

    # avoid double claiming
    with brownie.reverts("No pending rewards"):
        badger_tree.claim(
            vaults[0], want_whale, {"from": want_whale}
        )
