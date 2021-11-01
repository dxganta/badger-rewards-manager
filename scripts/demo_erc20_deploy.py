from brownie import (
    accounts,
    DemoERC20,
)
from config import PAUSER, SCHEDULER
from brownie import *
from dotmap import DotMap

import click
from rich.console import Console

console = Console()


def main():
    owner = connect_account()
    name = 'want-B'

    # Deploy erc20 contract
    token = DemoERC20.deploy(
        name,
        name,
        {"from": owner},
        publish_source=True
    )

    return DotMap(
        deployer=owner,
        token=token,
    )


def connect_account():
    click.echo(f"You are using the '{network.show_active()}' network")
    dev = accounts.load(click.prompt(
        "Account", type=click.Choice(accounts.load())))
    click.echo(f"You are using: 'dev' [{dev.address}]")
    return dev

# reward-A = 0x1a699421130e848aB0A5DC72B0b984dc7f7BD7C4
# reward-B = 0xFe21F123D04aF99A06AD12595487C0eA32029F51
# reward-C = 0xC05aF76792A2aaF334bF0cd9Ca25aF4220caAc89
# want-A = 0xe466fBF883c5A91a2C7bcD5e2B1e7c84858514A8
# want-B =
