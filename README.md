# New Rewards Manager Contract for BADGER DAO


# Tests
1. Test that if deposit & withdraw is done in the same block then rewards are zero.

2. Add new reward Token & Tests for it.

3. Also add a production_deploy.sol file




## Gas costs (BadgerTreeV3)
1. Deposit => 198406
2. addSetRewards => 64832
3. add => 93878
4. claim => 195526 (for 1 reward token), 238474 (for 2 reward tokens), 280230 (for 3 reward tokens)
5. withdraw => 75588