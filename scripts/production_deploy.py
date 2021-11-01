from brownie import (
    accounts,
    BadgerTreeV3,
)
from config import PAUSER, SCHEDULER
from brownie import *
from dotmap import DotMap

import click
from rich.console import Console

console = Console()


def main():
    owner = connect_account()

    # Deploy rewards contract
    badger_tree = BadgerTreeV3.deploy(
        SCHEDULER,
        PAUSER,
        {"from": owner},
        publish_source=True
    )

    return DotMap(
        deployer=owner,
        badger_tree=badger_tree,
    )


def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt(
        "Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev
