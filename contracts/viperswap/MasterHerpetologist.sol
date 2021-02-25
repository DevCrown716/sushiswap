// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ViperToken.sol";
import "./Authorizable.sol";

// MasterHerpetologist is the master of Viper. He can make Viper and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Viper is sufficiently
// distributed and the community can show to govern itself.
//
contract MasterHerpetologist is Ownable, Authorizable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardDebtAtBlock; // the last block user stake
        uint256 lastWithdrawBlock; // the last block a user withdrew at.
        uint256 firstDepositBlock; // the last block a user deposited at.
        uint256 blockdelta; //time passed since withdrawals
        uint256 lastDepositBlock;
        //
        // We do some fancy math here. Basically, any point in time, the amount of Vipers
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accViperPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accViperPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserGlobalInfo {
        uint256 globalAmount;
        mapping(address => uint256) referrals;
        uint256 totalReferals;
        uint256 globalRefAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Vipers to distribute per block.
        uint256 lastRewardBlock; // Last block number that Vipers distribution occurs.
        uint256 accViperPerShare; // Accumulated Vipers per share, times 1e12. See below.
    }

    // The Viper TOKEN!
    ViperToken public Viper;
    //An ETH/USDC Oracle (Chainlink)
    address public usdOracle;
    // Dev address.
    address public devAddr;
    // LP address
    address public liquidityAddr;
    // Community Fund Address
    address public communityFundAddr;
    // Founder Reward
    address public founderAddr;
    // Viper tokens created per block.
    uint256 public REWARD_PER_BLOCK;
    // Bonus muliplier for early Viper makers - each array element represents a week.
    uint256[] public REWARD_MULTIPLIER = [
        4096,
        2048,
        2048,
        1024,
        1024,
        512,
        512,
        256,
        256,
        256,
        256,
        256,
        256,
        256,
        256,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        16,
        8,
        8,
        8,
        8,
        32,
        32,
        64,
        64,
        64,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        256,
        256,
        256,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        128,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        64,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        32,
        16,
        16,
        16,
        16,
        8,
        8,
        8,
        4,
        2,
        1,
        0
    ];
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    uint256[] public blockDeltaStartStage;
    uint256[] public blockDeltaEndStage;
    uint256[] public userFeeStage;
    uint256[] public devFeeStage;
    uint256 public FINISH_BONUS_AT_BLOCK;
    uint256 public userDepFee;
    uint256 public devDepFee;

    // The block number when Viper mining starts.
    uint256 public START_BLOCK;

    uint256 public PERCENT_LOCK_BONUS_REWARD; // lock xx% of bounus reward in 3 year
    uint256 public PERCENT_FOR_DEV; // dev bounties + partnerships
    uint256 public PERCENT_FOR_LP; // LP fund
    uint256 public PERCENT_FOR_COMMUNITY; // community fund
    uint256 public PERCENT_FOR_FOUNDERS; // founders fund

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public poolId1; // poolId1 count from 1, subtraction 1 before using with poolInfo
    // Info of each user that stakes LP tokens. pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => UserGlobalInfo) public userGlobalInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SendViperReward(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 lockAmount
    );

    constructor(
        ViperToken _Viper,
        address _devAddr,
        address _liquidityAddr,
        address _communityFundAddr,
        address _founderAddr,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock,
        uint256 _userDepFee,
        uint256 _devDepFee,
        uint256[] memory _blockDeltaStartStage,
        uint256[] memory _blockDeltaEndStage,
        uint256[] memory _userFeeStage,
        uint256[] memory _devFeeStage
    ) public {
        Viper = _Viper;
        devAddr = _devAddr;
        liquidityAddr = _liquidityAddr;
        communityFundAddr = _communityFundAddr;
        founderAddr = _founderAddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        userDepFee = _userDepFee;
        devDepFee = _devDepFee;
        blockDeltaStartStage = _blockDeltaStartStage;
        blockDeltaEndStage = _blockDeltaEndStage;
        userFeeStage = _userFeeStage;
        devFeeStage = _devFeeStage;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock =
                _halvingAfterBlock.add(i + 1).add(_startBlock);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock
            .mul(REWARD_MULTIPLIER.length - 1)
            .add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        require(
            poolId1[address(_lpToken)] == 0,
            "MasterHerpetologist::add: lp is already in pool"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > START_BLOCK ? block.number : START_BLOCK;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolId1[address(_lpToken)] = poolInfo.length + 1;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accViperPerShare: 0
            })
        );
    }

    // Update the given pool's Viper allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 ViperForDev;
        uint256 ViperForFarmer;
        uint256 ViperForLP;
        uint256 ViperForCom;
        uint256 ViperForFounders;
        (
            ViperForDev,
            ViperForFarmer,
            ViperForLP,
            ViperForCom,
            ViperForFounders
        ) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
        Viper.mint(address(this), ViperForFarmer);
        pool.accViperPerShare = pool.accViperPerShare.add(
            ViperForFarmer.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
        if (ViperForDev > 0) {
            Viper.mint(address(devAddr), ViperForDev);
            //Dev fund has xx% locked during the starting bonus period. After which locked funds drip out linearly each block over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                Viper.lock(address(devAddr), ViperForDev.mul(75).div(100));
            }
        }
        if (ViperForLP > 0) {
            Viper.mint(liquidityAddr, ViperForLP);
            //LP + Partnership fund has only xx% locked over time as most of it is needed early on for incentives and listings. The locked amount will drip out linearly each block after the bonus period.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                Viper.lock(address(liquidityAddr), ViperForLP.mul(45).div(100));
            }
        }
        if (ViperForCom > 0) {
            Viper.mint(communityFundAddr, ViperForCom);
            //Community Fund has xx% locked during bonus period and then drips out linearly over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                Viper.lock(
                    address(communityFundAddr),
                    ViperForCom.mul(85).div(100)
                );
            }
        }
        if (ViperForFounders > 0) {
            Viper.mint(founderAddr, ViperForFounders);
            //The Founders reward has xx% of their funds locked during the bonus period which then drip out linearly per block over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                Viper.lock(
                    address(founderAddr),
                    ViperForFounders.mul(95).div(100)
                );
            }
        }
    }

    // |--------------------------------------|
    // [20, 30, 40, 50, 60, 70, 80, 99999999]
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        uint256 result = 0;
        if (_from < START_BLOCK) return 0;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    function getPoolReward(
        uint256 _from,
        uint256 _to,
        uint256 _allocPoint
    )
        public
        view
        returns (
            uint256 forDev,
            uint256 forFarmer,
            uint256 forLP,
            uint256 forCom,
            uint256 forFounders
        )
    {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount =
            multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(
                totalAllocPoint
            );
        uint256 ViperCanMint = Viper.cap().sub(Viper.totalSupply());

        if (ViperCanMint < amount) {
            forDev = 0;
            forFarmer = ViperCanMint;
            forLP = 0;
            forCom = 0;
            forFounders = 0;
        } else {
            forDev = amount.mul(PERCENT_FOR_DEV).div(100);
            forFarmer = amount;
            forLP = amount.mul(PERCENT_FOR_LP).div(100);
            forCom = amount.mul(PERCENT_FOR_COMMUNITY).div(100);
            forFounders = amount.mul(PERCENT_FOR_FOUNDERS).div(100);
        }
    }

    // View function to see pending Vipers on frontend.
    function pendingReward(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accViperPerShare = pool.accViperPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 ViperForFarmer;
            (, ViperForFarmer, , , ) = getPoolReward(
                pool.lastRewardBlock,
                block.number,
                pool.allocPoint
            );
            accViperPerShare = accViperPerShare.add(
                ViperForFarmer.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accViperPerShare).div(1e12).sub(user.rewardDebt);
    }

    function claimReward(uint256 _pid) public {
        updatePool(_pid);
        _harvest(_pid);
    }

    // lock 95% of reward if it come from bounus time
    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accViperPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            uint256 masterBal = Viper.balanceOf(address(this));

            if (pending > masterBal) {
                pending = masterBal;
            }

            if (pending > 0) {
                Viper.transfer(msg.sender, pending);
                uint256 lockAmount = 0;
                if (user.rewardDebtAtBlock <= FINISH_BONUS_AT_BLOCK) {
                    lockAmount = pending.mul(PERCENT_LOCK_BONUS_REWARD).div(
                        100
                    );
                    Viper.lock(msg.sender, lockAmount);
                }

                user.rewardDebtAtBlock = block.number;

                emit SendViperReward(msg.sender, _pid, pending, lockAmount);
            }

            user.rewardDebt = user.amount.mul(pool.accViperPerShare).div(1e12);
        }
    }

    function getGlobalAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalAmount;
    }

    function getGlobalRefAmount(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalRefAmount;
    }

    function getTotalRefs(address _user) public view returns (uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.totalReferals;
    }

    function getRefValueOf(address _user, address _user2)
        public
        view
        returns (uint256)
    {
        UserGlobalInfo storage current = userGlobalInfo[_user];
        uint256 a = current.referrals[_user2];
        return a;
    }

    // Deposit LP tokens to MasterHerpetologist for $VIPER allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _ref
    ) public {
        require(
            _amount > 0,
            "MasterHerpetologist::deposit: amount must be greater than 0"
        );

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserInfo storage devr = userInfo[_pid][devAddr];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];

        if (refer.referrals[msg.sender] > 0) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        } else {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            refer.totalReferals = refer.totalReferals + 1;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        }

        current.globalAmount =
            current.globalAmount +
            _amount.mul(userDepFee).div(100);

        updatePool(_pid);
        _harvest(_pid);
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (user.amount == 0) {
            user.rewardDebtAtBlock = block.number;
        }
        user.amount = user.amount.add(
            _amount.sub(_amount.mul(userDepFee).div(10000))
        );
        user.rewardDebt = user.amount.mul(pool.accViperPerShare).div(1e12);
        devr.amount = devr.amount.add(
            _amount.sub(_amount.mul(devDepFee).div(10000))
        );
        devr.rewardDebt = devr.amount.mul(pool.accViperPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
        if (user.firstDepositBlock > 0) {} else {
            user.firstDepositBlock = block.number;
        }
        user.lastDepositBlock = block.number;
    }

    // Withdraw LP tokens from MasterHerpetologist.
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _ref
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];
        require(
            user.amount >= _amount,
            "MasterHerpetologist::withdraw: not good"
        );
        if (_ref != address(0)) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] - _amount;
            refer.globalRefAmount = refer.globalRefAmount - _amount;
        }
        current.globalAmount = current.globalAmount - _amount;

        updatePool(_pid);
        _harvest(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (user.lastWithdrawBlock > 0) {
                user.blockdelta = block.number - user.lastWithdrawBlock;
            } else {
                user.blockdelta = block.number - user.firstDepositBlock;
            }
            if (
                user.blockdelta == blockDeltaStartStage[0] ||
                block.number == user.lastDepositBlock
            ) {
                //25% fee for withdrawals of LP tokens in the same block this is to prevent abuse from flashloans
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[0]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[0]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[1] &&
                user.blockdelta <= blockDeltaEndStage[0]
            ) {
                //8% fee if a user deposits and withdraws in under between same block and 59 minutes.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[1]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[1]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[2] &&
                user.blockdelta <= blockDeltaEndStage[1]
            ) {
                //4% fee if a user deposits and withdraws after 1 hour but before 1 day.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[2]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[2]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[3] &&
                user.blockdelta <= blockDeltaEndStage[2]
            ) {
                //2% fee if a user deposits and withdraws between after 1 day but before 3 days.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[3]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[3]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[4] &&
                user.blockdelta <= blockDeltaEndStage[3]
            ) {
                //1% fee if a user deposits and withdraws after 3 days but before 5 days.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[4]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[4]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[5] &&
                user.blockdelta <= blockDeltaEndStage[4]
            ) {
                //0.5% fee if a user deposits and withdraws if the user withdraws after 5 days but before 2 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[5]).div(1000)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[5]).div(1000)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[6] &&
                user.blockdelta <= blockDeltaEndStage[5]
            ) {
                //0.25% fee if a user deposits and withdraws after 2 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[6]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[6]).div(10000)
                );
            } else if (user.blockdelta > blockDeltaStartStage[7]) {
                //0.1% fee if a user deposits and withdraws after 4 weeks.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[7]).div(10000)
                );
                pool.lpToken.safeTransfer(
                    address(devAddr),
                    _amount.mul(devFeeStage[7]).div(10000)
                );
            }
            user.rewardDebt = user.amount.mul(pool.accViperPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
            user.lastWithdrawBlock = block.number;
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY. This has the same 25% fee as same block withdrawals to prevent abuse of thisfunction.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //reordered from Sushi function to prevent risk of reentrancy
        uint256 amountToSend = user.amount.mul(75).div(100);
        uint256 devToSend = user.amount.mul(25).div(100);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amountToSend);
        pool.lpToken.safeTransfer(address(devAddr), devToSend);
        emit EmergencyWithdraw(msg.sender, _pid, amountToSend);
    }

    // Safe Viper transfer function, just in case if rounding error causes pool to not have enough Vipers.
    function safeViperTransfer(address _to, uint256 _amount) internal {
        uint256 ViperBal = Viper.balanceOf(address(this));
        if (_amount > ViperBal) {
            Viper.transfer(_to, ViperBal);
        } else {
            Viper.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) public onlyAuthorized {
        devAddr = _devAddr;
    }

    // Update Finish Bonus Block
    function bonusFinishUpdate(uint256 _newFinish) public onlyAuthorized {
        FINISH_BONUS_AT_BLOCK = _newFinish;
    }

    // Update Halving At Block
    function halvingUpdate(uint256[] memory _newHalving) public onlyAuthorized {
        HALVING_AT_BLOCK = _newHalving;
    }

    // Update Liquidityaddr
    function lpUpdate(address _newLP) public onlyAuthorized {
        liquidityAddr = _newLP;
    }

    // Update communityFundAddr
    function comUpdate(address _newCom) public onlyAuthorized {
        communityFundAddr = _newCom;
    }

    // Update founderAddr
    function founderUpdate(address _newFounder) public onlyAuthorized {
        founderAddr = _newFounder;
    }

    // Update Reward Per Block
    function rewardUpdate(uint256 _newReward) public onlyAuthorized {
        REWARD_PER_BLOCK = _newReward;
    }

    // Update Rewards Mulitplier Array
    function rewardMulUpdate(uint256[] memory _newMulReward)
        public
        onlyAuthorized
    {
        REWARD_MULTIPLIER = _newMulReward;
    }

    // Update % lock for general users
    function lockUpdate(uint256 _newGeneralLock) public onlyAuthorized {
        PERCENT_LOCK_BONUS_REWARD = _newGeneralLock;
    }

    // Update % lock for dev
    function lockDevUpdate(uint256 _newDevLock) public onlyAuthorized {
        PERCENT_FOR_DEV = _newDevLock;
    }

    // Update % lock for LP
    function lockLpUpdate(uint256 _newLpLock) public onlyAuthorized {
        PERCENT_FOR_LP = _newLpLock;
    }

    // Update % lock for COM
    function lockCommunityUpdate(uint256 _newCommunityLock) public onlyAuthorized {
        PERCENT_FOR_COMMUNITY = _newCommunityLock;
    }

    // Update % lock for Founders
    function lockFounderUpdate(uint256 _newFounderLock) public onlyAuthorized {
        PERCENT_FOR_FOUNDERS = _newFounderLock;
    }

    // Update START_BLOCK
    function startBlockUpdate(uint256 _newStartBlock) public onlyAuthorized {
        START_BLOCK = _newStartBlock;
    }

    function getNewRewardPerBlock(uint256 pid1) public view returns (uint256) {
        uint256 multiplier = getMultiplier(block.number - 1, block.number);
        if (pid1 == 0) {
            return multiplier.mul(REWARD_PER_BLOCK);
        } else {
            return
                multiplier
                    .mul(REWARD_PER_BLOCK)
                    .mul(poolInfo[pid1 - 1].allocPoint)
                    .div(totalAllocPoint);
        }
    }

    function userDelta(uint256 _pid) public view returns (uint256) {
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.lastWithdrawBlock > 0) {
            uint256 estDelta = block.number - user.lastWithdrawBlock;
            return estDelta;
        } else {
            uint256 estDelta = block.number - user.firstDepositBlock;
            return estDelta;
        }
    }

    function reviseWithdraw(
        uint256 _pid,
        address _user,
        uint256 _block
    ) public onlyAuthorized() {
        UserInfo storage user = userInfo[_pid][_user];
        user.lastWithdrawBlock = _block;
    }

    function reviseDeposit(
        uint256 _pid,
        address _user,
        uint256 _block
    ) public onlyAuthorized() {
        UserInfo storage user = userInfo[_pid][_user];
        user.firstDepositBlock = _block;
    }

    function setStageStarts(uint256[] memory _blockStarts)
        public
        onlyAuthorized()
    {
        blockDeltaStartStage = _blockStarts;
    }

    function setStageEnds(uint256[] memory _blockEnds) public onlyAuthorized() {
        blockDeltaEndStage = _blockEnds;
    }

    function setUserFeeStage(uint256[] memory _userFees)
        public
        onlyAuthorized()
    {
        userFeeStage = _userFees;
    }

    function setDevFeeStage(uint256[] memory _devFees) public onlyAuthorized() {
        devFeeStage = _devFees;
    }

    function setDevDepFee(uint256 _devDepFees) public onlyAuthorized() {
        devDepFee = _devDepFees;
    }

    function setUserDepFee(uint256 _usrDepFees) public onlyAuthorized() {
        userDepFee = _usrDepFees;
    }
}
