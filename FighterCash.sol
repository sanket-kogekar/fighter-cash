// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Rules & Guidelines: https://docs.google.com/document/d/17DAZQjoCPPnzbFb-TR_-xw4LARPxZGLzBSibnY4UMq4/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FighterCash is Ownable {
    // USDC on Polygon
    using SafeERC20 for IERC20;
    IERC20 public USDC; //= IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); << USDC on Polygon

    uint8 public winningFighter;
    bool public bettingPaused;
    bool public winnerDeclared;
    bool public feeCollected;
    mapping(address => mapping(uint8 => uint256)) public userBets;
    mapping(uint8 => uint256) public totalBetAmount;

    event BettingPaused();
    event BettingResumed();
    event BetPlaced(address indexed user, uint8 fighter, uint256 amount);
    event WinnerDeclared(uint8 indexed fighter);
    event RewardWithdrawn(address indexed user, uint256 amount);
    event ApprovalSuccessful(address indexed user, address contr, uint256 amount);
    event ApprovalFailed(address indexed user, address contr, uint256 amount);

    constructor(address addr) Ownable(msg.sender) {
        USDC = IERC20(addr);
    }

    // Fighters: [1] vs [2]
    function placeBet(uint8 fighter, uint256 amount) external {
        require(!bettingPaused, "Betting is paused");
        require(!winnerDeclared, "Winner has already been declared");
        require(fighter == 1 || fighter == 2, "Invalid fighter");
        // Minimum betting amount set below
        require(amount >= 10 * 1e6, "Minimum bet must be 10 USDC");

        userBets[msg.sender][fighter] += amount;
        totalBetAmount[fighter] += amount;

        SafeERC20.safeTransferFrom(USDC, msg.sender, address(this), amount);
        emit BetPlaced(msg.sender, fighter, amount);
    }

    function declareWinner(uint8 fighter) external onlyOwner {
        require(!winnerDeclared, "Winner has already been declared");
        require(fighter == 1 || fighter == 2, "Invalid fighter");
        require(
            bettingPaused,
            "Betting must be paused before declaring winner"
        );

        winningFighter = fighter;
        winnerDeclared = true;

        emit WinnerDeclared(fighter);
    }

    function withdrawReward() external {
        require(winnerDeclared, "Winner has not been declared");
        uint256 userBet = userBets[msg.sender][winningFighter];

        require(userBet > 0, "No bets on winning fighter");
        require(USDC.balanceOf(address(this)) > 0, "No USDC to distribute");

        uint256 totalWinnerBets = totalBetAmount[winningFighter];
        require(totalWinnerBets > 0, "No bets on winning fighter");

        // Calculate the total pool available for rewards
        uint256 totalPool = totalBetAmount[1] + totalBetAmount[2];
        uint256 rewardPool = (totalPool * 9) / 10;  // 90% of the total pool

        // Calculate the user's share and reward
        uint256 reward = (rewardPool * userBet) / totalWinnerBets;  // Calculate the reward based on the user's share

        // Ensure the user does not withdraw again
        userBets[msg.sender][winningFighter] = 0;

        SafeERC20.safeTransfer(USDC, msg.sender, reward);

        emit RewardWithdrawn(msg.sender, reward);
    }

    function collectFees(address to) external onlyOwner {
        require(winnerDeclared, "Winner has not been declared");
        require(bettingPaused, "Betting must be paused to collect fees");
        require(!feeCollected, "Fees already collected");
        feeCollected = true;
        uint256 feeAmount = (totalBetAmount[1] + totalBetAmount[2]) / 10;
        SafeERC20.safeTransfer(USDC, to, feeAmount);
    }

    function pause() external onlyOwner {
        require(!bettingPaused, "Betting already paused");
        bettingPaused = true;
        emit BettingPaused();
    }

    function resume() external onlyOwner {
        require(bettingPaused, "Betting already resumed");
        bettingPaused = false;
        emit BettingResumed();
    }

    function viewWithdrawAmount(address user) external view returns (uint256) {
        require(winnerDeclared, "Winner has not been declared");
        uint256 userBet = userBets[user][winningFighter];

        require(userBet > 0, "No bets on winning fighter");
        require(USDC.balanceOf(address(this)) > 0, "No USDC to distribute");

        uint256 totalWinnerBets = totalBetAmount[winningFighter];
        require(totalWinnerBets > 0, "No bets on winning fighter");

        // Calculate the total pool available for rewards
        uint256 totalPool = totalBetAmount[1] + totalBetAmount[2];
        uint256 rewardPool = (totalPool * 9) / 10;  // 90% of the total pool

        // Calculate the user's share and reward
        uint256 reward = (rewardPool * userBet) / totalWinnerBets;  // Calculate the reward based on the user's share

        return reward;
    }

    // In the case when fight is cancelled or has any issue with declaring results
    // (happens very rarely: fighters get injured, tests positive for PEDs, etc):
    // Entire USDC will be manually returned to participants
    // (as if the betting never took place)
    function emergencyWithdraw(address to) external onlyOwner {
        SafeERC20.safeTransfer(USDC, to, USDC.balanceOf(address(this)));
    }
}   
