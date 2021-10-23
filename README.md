# New Rewards Manager Contract for BADGER DAO


# Tests
1. Test that if deposit & withdraw is done in the same block then rewards are zero.

Start with notifyTransfer
  - Does balance work?
   - 1 user 1 vault
    - 1 user 2 vaults
    - 2 users 1 vaults

 - Does callign update sett work?
   - Update set
  - deposit and update set
  - depoist, deposit and update set
  - deposit, update set, and deposit again

 - Check math of pending rewards with above 
 
 - addSetRewards
  - Once per sett and then deposit
  - Once per sett and then multiple people deposit (3 accounts)
 - Add, then deposit then add again