from helpers.constants import *
from brownie import Wei, chain


def test_break(deployer, vaults, badger_tree, want_whale, want, accounts):
    want.approve(vaults[0], MaxUint256, {"from": want_whale})

    badger_tree.add(vaults[0], [], {"from": deployer})

    # accounts[0] is _scheduler & _pauser, 7200 blocks
    badger_emitted = 100
    badger_tree.addSettRewards(
        vaults[0], 7200, [Wei(f"{badger_emitted} ether")], {
            "from": accounts[0]}
    )

    print(want.balanceOf(want_whale))

    # user 1st deposit
    vaults[0].deposit(want.balanceOf(want_whale) * 0.05, {"from": want_whale})

    chain.mine(100)

    reward_pending_before = badger_tree.pendingRewards(vaults[0], want_whale)[
        0]

    # same user 2nd deposit
    vaults[0].deposit(want.balanceOf(want_whale) * 0.05, {"from": want_whale})

    reward_pending_after = badger_tree.pendingRewards(vaults[0], want_whale)[0]

    # should be higher badger rewards, right? TOFIX!
    assert reward_pending_after > reward_pending_before

# The error is because of how the lpSupply is calculated
# since now we are reading the lpSupply directly from the vault
# so now when a seconde deposit is made, and updateSett is called
# it is calculating lpSupply which has already been incremented due to the share addition

# Fix was to call the updateSett function in the SettV3 contract itself before the mint & burn functions are called
