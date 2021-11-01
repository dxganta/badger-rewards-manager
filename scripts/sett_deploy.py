from brownie import (
    accounts,
    SettV3,
    Controller
)
from config import PAUSER, SCHEDULER
from brownie import *
from dotmap import DotMap

import click
from rich.console import Console

console = Console()


def deploy_vault(dev, badger_tree, want, sett_name):
    controller = Controller.deploy({"from": dev})
    controller.initialize(
        dev,
        dev,
        dev,
        dev
    )

    # deploy vault
    vault = SettV3.deploy(
        {"from": dev},
        publish_source=True
    )

    vault.initialize(
        want,
        controller,
        dev,
        dev,
        dev,
        badger_tree,
        True,
        sett_name,
        sett_name,
        {"from": dev}
    )

    vault.unpause({"from": dev})
    controller.setVault(want, vault)

    return vault


def main():
    owner = connect_account()
    badger_tree = "0x662f38c312A7a6742454E96AB89e9ce4c84C244D"
    name = 'sett-B'
    want = "0xB332685f94793dC2aaD5dF11EedB744f572849d9"

    # Deploy sett
    sett = deploy_vault(owner, badger_tree, want, name)

    return DotMap(
        deployer=owner,
        sett=sett,
    )


def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt(
        "Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev
