// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./MasterChefV2.sol";
import "./BambooBar.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompoundingBamboo is ERC20("CompoundingBamboo", "cBAMBOO"), Ownable {
    using SafeMath for uint;
    uint totalDeposits; 

    // constants
    MasterChefV2 public stakingContract; // MasterChef
    BambooBar public sBamboo;
    IERC20 public depositToken; // Bamboo
    IERC20 public rewardToken; // Bamboo
    uint public _totalSupply = totalSupply();
    uint public PID;
    uint public MIN_TOKENS_TO_REINVEST = 20;
    uint public REINVEST_REWARD_BIPS = 500;     // 5%
    uint public ADMIN_FEE_BIPS = 500;           // 5%
    uint constant private BIPS_DIVISOR = 10000;
    uint constant private UINT_MAX = uint(-1);
    // TODO add latest configuration variables

    event Deposit(address indexed account, uint amount);
    event Withdraw(address indexed account, uint amount);
    event Reinvest(uint newTotalDeposits, uint newTotalSupply);
    event Recovered(address token, uint amount);
    event UpdateAdminFee(uint oldValue, uint newValue);
    event UpdateReinvestReward(uint oldValue, uint newValue);
    event UpdateMinTokensToReinvest(uint oldValue, uint newValue);
    // TODO add latest events

    constructor(address _sBamboo, address _Bamboo, address _masterChef, uint _pid) public {
        sBamboo    = IERC20(_sBamboo);
        Bamboo     = IERC20(_Bamboo);
        stakingContract = MasterChefV2(_masterChef);
        Bamboobar  = BambooBar(_sBamboo);
        PID = _pid;
        setAllowances();}
        
    function setAllowances() public onlyOwner {
        depositToken.approve(address(sBamboo), UINT_MAX);
        sBamboo.approve(address(stakingContract), UINT_MAX);
    }

    function revokeAllowance(address token, address spender) external onlyOwner {
        IERC20(token).approve(spender, 0);
    }

    // make sure caller isn't a contract
    modifier onlyEOA() {
      require(tx.origin == msg.sender, "onlyEOA");
      _;}

    // deposits
    function deposit(uint amount) external {_deposit(amount);}

    function depositWithPermit(uint amount) external {
        // TODO - add permit functionality for smoother deposits
        _deposit(amount);
    }

    function _deposit(uint amount) internal {
        require(amount > 0, "amount too small");
        require(totalDeposits >= _totalSupply, "deposit failed");
        require(depositToken.transferFrom(msg.sender, address(this), amount), "transferFrom() failed");
        uint sBambooAmount = _convertBambooToSBamboo(amount);
        _stakeSBamboo(sBambooAmount);
        _mint(msg.sender, getSharesForDepositToken(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(msg.sender, amount);}
        
    // deposit with sSamboo
    function depositSBamboo(uint amount) external {_depositSBamboo(amount);}

    function depositSBambooWithPermit(uint amount) external {
        // TODO - add permit functionality for smoother deposits
        _depositSBamboo(amount);
    }

    function _depositSBamboo(uint amount) internal {
        require(amount > 0, "amount too small");
        require(totalDeposits >= _totalSupply, "deposit failed");
        require(sBamboo.transferFrom(msg.sender, address(this), amount), "transferFrom() failed");
        uint bambooAmount = getBambooForSBamboo(amount);
        _stakeSBamboo(amount);
        _mint(msg.sender, getSharesForDepositTokens(bambooAmount));
        totalDeposits = totalDeposits.add(bambooAmount);
        emit Deposit(msg.sender, bambooAmount);}
        
    // withdraws
    function withdraw(uint amount) external {
        uint bambooAmount = getDepositTokensForShares(amount);
        uint sBambooAmount = 0; // todo- must fix - add conversion math - ensure assets won't lock up here
        if (sBambooAmount > 0) {
        _withdrawSBamboo(sBambooAmount);
        require(depositToken.transfer(msg.sender, bambooAmount), "transfer failed");
        _burn(msg.sender, amount);
        totalDeposits = totalDeposits.sub(bambooAmount);
        emit Withdraw(msg.sender, bambooAmount);}}

    function _withdraw(uint amount) internal {
        require(amount > 0, "amount too low");
        stakingContract.withdraw(PID, amount);
        // todo: convert sBamboo to bamboo
        }

    // get rates of exchange
    function getSharesForDepositTokens(uint amount) public view returns (uint) {
        if (_totalSupply.mul(totalDeposits) == 0) {return amount;}
        return amount.mul(_totalSupply).div(totalDeposits);}

    function getDepositTokensForShares(uint amount) public view returns (uint) {
        if (_totalSupply.mul(totalDeposits) == 0) {return 0;}
        return amount.mul(totalDeposits).div(_totalSupply);}
    
    function getBambooForSBamboo(uint amount) public view returns (uint) {
        // TODO
    }

    // current total pending reward for frontend
    function checkReward() public view returns (uint) {
        uint pendingReward = stakingContract.pendingBamboo(PID, address(this));
        uint contractBalance = rewardToken.balanceOf(address(this));
        return pendingReward.add(contractBalance);}

    // internal functionality for staking into the masterchef
    function _stakeSBamboo(uint amount) internal {
        require(amount > 0, "amount too low");
        stakingContract.deposit(PID, amount);}

    // Update reinvest minimum earned bamboo threshold
    function updateMinTokensToReinvest(uint newValue) external onlyOwner {
        emit UpdateMinTokensToReinvest(MIN_TOKENS_TO_REINVEST, newValue);
        MIN_TOKENS_TO_REINVEST = newValue;}

    // Update reinvest reward for caller
    function updateReinvestReward(uint newValue) external onlyOwner {
        require(newValue.add(ADMIN_FEE_BIPS) <= BIPS_DIVISOR, "reinvest reward too high");
        emit UpdateReinvestReward(REINVEST_REWARD_BIPS, newValue);
        REINVEST_REWARD_BIPS = newValue;}
    
    // estimate reward from calling reinvest for the frontend
    function estimateReinvestReward() external view returns (uint) {
        uint unclaimedRewards = checkReward();
        if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST) {return unclaimedRewards.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);}
        return 0;}

    function updateAdminFee(uint newValue) external onlyOwner {
        require(newValue.add(REINVEST_REWARD_BIPS) <= BIPS_DIVISOR, "admin fee too high");
        emit UpdateAdminFee(ADMIN_FEE_BIPS, newValue);
        ADMIN_FEE_BIPS = newValue;}

    function reinvest() external onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "MIN_TOKENS_TO_REINVEST");
        // harvests
        stakingContract.deposit(PID, 0);
        
        // pays admin
        uint adminFee = unclaimedRewards.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {require(rewardToken.transfer(owner(), adminFee), "admin fee transfer failed");}
        
        // pays caller
        uint reinvestFee = unclaimedRewards.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {require(rewardToken.transfer(msg.sender, reinvestFee), "reinvest fee transfer failed");}
        
        // convert rewarded Bamboo to sBamboo, then restakes
        uint bambooAmount = unclaimedRewards.sub(adminFee).sub(reinvestFee);
        uint sBambooAmount = _convertBambooToSBamboo(bambooAmount); // todo - check this won't overestimate
        _stakeSBamboo(sBambooAmount);
        totalDeposits = totalDeposits.add(bambooAmount);
        emit Reinvest(totalDeposits, _totalSupply);}

    // enters bamboobar, aka swaps bamboo for bamboo
    function _convertBambooToSBamboo(uint amount) internal returns (uint) {
        Bamboobar.enter(amount);
        // TODO - add return value of sbamboo
        }
}
