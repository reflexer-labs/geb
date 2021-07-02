import unittest
from collections import defaultdict
from decimal import Decimal


"""
Rapid prototype model of rai liquidation pool for additional verification and low effort experiments of how this
can be achieved without excessive gas usage. Ultra simple mocks replace the GEB architecture and low level
implementation details of solidity, while writing solidity style python for simple translation.

Liquidations will remove system coins while shares held by accounts will be constant, meanwhile accounts will be
depositing and withdrawing system coins and shares can not be updated.

In addition collateral rewards for each account must be stored without iterating over the entire share map.
The pool achieves this with use of careful offsets and scale factors.

PEP8 is ignored in favour of matching solidity names.
"""


class Token:
    def __init__(self):
        self.address_to_balance = {1: Decimal('10'),
                                   2: Decimal('10'),
                                   3: Decimal('10'),
                                   4: Decimal('10'),
                                   5: Decimal('10'),
                                   6: Decimal('10'),
                                   7: Decimal('10'),
                                   8: Decimal('10'),
                                   9: Decimal('10'),
                                   10: Decimal('1000'),
                                   }

    def transfer(self, from_add, to_add, quantity):
        self.address_to_balance[from_add] -= quantity
        self.address_to_balance[to_add] += quantity
        assert self.address_to_balance[from_add] >= Decimal('0')


class LiquidityPool:
    def __init__(self, rai, eth):
        self.system_coin = rai
        self.collateral_coin = eth
        self.sysCoinShares = defaultdict(Decimal)
        self.totalSysCoinShares = Decimal('0')
        self.pooledSystemCoins = Decimal('0')

        self.negativeRewardOffsets = defaultdict(Decimal)
        self.totalNegativeOffsets = Decimal('0')
        self.positiveRewardOffsets = defaultdict(Decimal)
        self.totalPositiveOffsets = Decimal('0')

        self.pooled_native_coins = Decimal('0')
        self.own_addr = 9
        self.liq_addr = 10

    def get_user_sys_coin_balance(self, address):
        return self.sysCoinShares[address] * self.sharesToSystemCoin()

    def systemCoinsToShares(self):
        if self.pooledSystemCoins == 0:
            return Decimal('1')
        return self.totalSysCoinShares / self.pooledSystemCoins

    def sharesToSystemCoin(self):
        if self.totalSysCoinShares == 0:
            return 0
        return self.pooledSystemCoins / self.totalSysCoinShares

    def perform_liquidation(self, sys_coins_to_pay, reward_quantity):
        self.collateral_coin.transfer(self.liq_addr, self.own_addr, reward_quantity)
        self.system_coin.transfer(self.own_addr, self.liq_addr, sys_coins_to_pay)
        self.pooled_native_coins += reward_quantity
        self.pooledSystemCoins -= sys_coins_to_pay

    def deposit(self, address, wad):
        """stake a quantity of users rai and adjust for existing rewards"""
        newShares = wad * self.systemCoinsToShares()
        self.sysCoinShares[address] += newShares
        newOffset = self.virtualCollateral()
        if self.totalSysCoinShares > 0:
            newOffset *= (newShares / self.totalSysCoinShares)
        self.totalNegativeOffsets += newOffset
        self.negativeRewardOffsets[address] += newOffset
        self.totalSysCoinShares += newShares
        self.pooledSystemCoins += wad
        self.system_coin.transfer(address, self.own_addr, wad)

    def withdrawSystemCoin(self, address, wad):
        """redeem a quantity of rai"""
        if self.get_user_sys_coin_balance(address) < wad:
            return
        shares = wad * self.systemCoinsToShares()
        rewardsShare = self.virtualCollateral() * (shares / self.totalSysCoinShares)
        self.positiveRewardOffsets[address] += rewardsShare
        self.totalPositiveOffsets += rewardsShare
        self.sysCoinShares[address] -= shares
        self.totalSysCoinShares -= shares
        self.pooledSystemCoins -= wad
        self.system_coin.transfer(self.own_addr, address, wad)

    def withdrawRewards(self, address):
        share = 1
        if self.totalSysCoinShares > 0:
            share = self.sysCoinShares[address] / self.totalSysCoinShares
        virtualReward = share * self.virtualCollateral()
        reward = virtualReward + self.positiveRewardOffsets[address] - self.negativeRewardOffsets[address]

        self.negativeRewardOffsets[address] += reward
        self.totalNegativeOffsets += reward
        self.collateral_coin.transfer(self.own_addr, address, reward)
        self.pooled_native_coins -= reward
        self.totalNegativeOffsets += reward

    def virtualCollateral(self):
        return self.pooled_native_coins + self.totalNegativeOffsets - self.totalPositiveOffsets


class TestLiquidationPool(unittest.TestCase):
    """
    Brief verification, this model can't be trusted to be a perfect representation of the contract but is useful for initial easy debugging.
    """
    def setUp(self):
        rai = Token()
        eth = Token()
        self.liquidity_pool = LiquidityPool(rai, eth)

    def test_deposits_and_withdrawals(self):
        self.liquidity_pool.deposit(1, Decimal('2'))
        self.liquidity_pool.deposit(2, Decimal('4'))
        self.liquidity_pool.perform_liquidation(Decimal('3'), Decimal('1'))
        self.liquidity_pool.deposit(3, Decimal('5'))
        self.liquidity_pool.withdrawRewards(3)
        self.liquidity_pool.withdrawRewards(1)

        self.assertEqual(self.liquidity_pool.get_user_sys_coin_balance(1), 1)
        self.assertEqual(self.liquidity_pool.get_user_sys_coin_balance(2), 2)
        self.assertAlmostEqual(float(self.liquidity_pool.collateral_coin.address_to_balance[1]), 10 + 1/3)  # starting balance was 10
        self.assertAlmostEqual(self.liquidity_pool.collateral_coin.address_to_balance[2], 10)  # starting balance was 10
        self.assertAlmostEqual(self.liquidity_pool.collateral_coin.address_to_balance[3], 10)  # starting balance was 10


if __name__ == '__main__':
    unittest.main()
