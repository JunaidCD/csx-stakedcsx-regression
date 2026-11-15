// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../contracts/CSX/StakedCSX.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockWETH.sol";
import "./mocks/MockKeepers.sol";

contract CSXStakingRegression_Fixed is Test {
    MockERC20 csx;
    MockWETH weth;
    MockERC20 usdc;
    MockERC20 usdt;
    MockKeepers keepers;
    StakedCSX staked;

    address keeper = address(0xBEEF);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address depositor = address(0xD0);

    uint256 constant STAKE_TOTAL = 8 ether;
    uint256 constant STAKE_ALICE = 1 ether;
    uint256 constant STAKE_BOB = 7 ether;
    uint256 constant REWARD_USDC = 800e6;

    function setUp() public {
        csx = new MockERC20("CSX", "CSX", 18);
        weth = new MockWETH();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        keepers = new MockKeepers();
        keepers.setKeeperNode(keeper, true);

        InitParams memory params = InitParams({
            KEEPERS_INTERFACE: address(keepers),
            TOKEN_CSX: address(csx),
            TOKEN_WETH: address(weth),
            TOKEN_USDC: address(usdc),
            TOKEN_USDT: address(usdt)
        });
        staked = new StakedCSX(params);

        csx.mint(alice, STAKE_ALICE);
        csx.mint(bob, STAKE_BOB);
        usdc.mint(depositor, REWARD_USDC);

        vm.startPrank(alice);
        csx.approve(address(staked), type(uint256).max);
        staked.stake(STAKE_ALICE);
        vm.stopPrank();

        vm.startPrank(bob);
        csx.approve(address(staked), type(uint256).max);
        staked.stake(STAKE_BOB);
        vm.stopPrank();

        // Set reward duration for fixed (time-based streaming) version
        vm.startPrank(keeper);
        staked.setRewardsDuration(1, address(usdc));
        vm.stopPrank();
    }

    function _depositAndDistributeUSDC(uint256 amount) internal {
        vm.startPrank(depositor);
        usdc.approve(address(staked), amount);
        staked.depositDividend(address(usdc), amount);
        vm.stopPrank();

        vm.prank(keeper);
        staked.distribute(false, true, false);

        // Make full streamed rewards available
        vm.warp(block.timestamp + 1);
    }

    function test_zeroValueTransfer_doesNotChangeRewardOf() public {
        _depositAndDistributeUSDC(REWARD_USDC);

        (uint256 usdcBefore,,) = staked.rewardOf(alice);

        vm.prank(alice);
        staked.transfer(bob, 0);

        (uint256 usdcAfter,,) = staked.rewardOf(alice);

        assertEq(usdcAfter, usdcBefore, "zero-value transfer must not change rewardOf");
    }

    function test_rewardProportionalityAndSolvency_afterRepeatedZeroTransfers() public {
        _depositAndDistributeUSDC(REWARD_USDC);

        (uint256 initialUsdc,,) = staked.rewardOf(alice);
        assertGt(initialUsdc, 0, "alice must have initial rewards");

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            staked.transfer(bob, 0);
            (uint256 usdcNow,,) = staked.rewardOf(alice);
            assertGe(usdcNow, initialUsdc, "entitlement tracked after transfer");
        }

        (uint256 finalUsdc,,) = staked.rewardOf(alice);
        uint256 aliceEntitled = finalUsdc;
        uint256 oneEighth = REWARD_USDC / 8;

        uint256 usdcBalanceBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        staked.claim(true, false, false, false);
        uint256 claimed = usdc.balanceOf(alice) - usdcBalanceBefore;

        assertLe(claimed, oneEighth, "alice must not claim more than 1/8 of rewards");
        assertLe(aliceEntitled, oneEighth, "alice entitlement must not exceed 1/8");

        assertLe(claimed, REWARD_USDC, "payout cannot exceed deposited rewards");
        (uint256 bobUsdc,,) = staked.rewardOf(bob);
        assertLe(bobUsdc, usdc.balanceOf(address(staked)) + 1, "contract must remain solvent for others");
    }

    function test_normalRewardDistribution_proportionalClaim() public {
        _depositAndDistributeUSDC(REWARD_USDC);

        uint256 expectedAlice = REWARD_USDC / 8;
        uint256 expectedBob = REWARD_USDC - expectedAlice;

        (uint256 aliceReward,,) = staked.rewardOf(alice);
        (uint256 bobReward,,) = staked.rewardOf(bob);

        assertApproxEqAbs(aliceReward, expectedAlice, 1, "alice proportional reward");
        assertApproxEqAbs(bobReward, expectedBob, 1, "bob proportional reward");

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        staked.claim(true, false, false, false);
        uint256 aliceClaimed = usdc.balanceOf(alice) - aliceUsdcBefore;
        assertApproxEqAbs(aliceClaimed, expectedAlice, 1, "alice claimed proportional amount");

        uint256 bobUsdcBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        staked.claim(true, false, false, false);
        uint256 bobClaimed = usdc.balanceOf(bob) - bobUsdcBefore;
        assertApproxEqAbs(bobClaimed, expectedBob, 1, "bob claimed proportional amount");
    }
}
