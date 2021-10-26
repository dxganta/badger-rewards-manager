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

For testing trasnfer
Do a vault contract
That triggers tht
When I mint shares
I get more points
When I burn shares
I get less points
When I burn after having accrued some points, my previous points grew by the original mint
But the new points will grow based on the new amount


## Gas costs (BadgerTreeV3)
1. Deposit => 198406
2. addSetRewards => 64832
3. add => 93878
4. claim => 195526 (for 1 reward token), 238474 (for 2 reward tokens), 280230 (for 3 reward tokens)
5. withdraw => 75588