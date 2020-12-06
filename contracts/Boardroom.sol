pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import './lib/Safe112.sol';
import './owner/Operator.sol';
import './utils/ContractGuard.sol';
import './interfaces/IBasisAsset.sol';

contract Boardroom is ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using Safe112 for uint112;

    /* ========== DATA STRUCTURES ========== */

    struct Boardseat {
        uint256 appointmentTime;
        uint256 shares;
    }

    struct BoardSnapshot {
        uint256 timestamp;
        uint256 rewardReceived;
        uint256 totalShares;
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 private cash;
    IERC20 private share;
    uint256 private DEFAULT_MAX_CLAIM_SNAPSHOTS = 365;

    mapping(address => Boardseat) private directors;
    BoardSnapshot[] private boardHistory;

    /* ========== CONSTRUCTOR ========== */

    constructor(IERC20 _cash, IERC20 _share) public {
        cash = _cash;
        share = _share;

        BoardSnapshot memory genesisSnapshot = BoardSnapshot(now, 0, 0);
        boardHistory.push(genesisSnapshot);
    }

    /* ========== Modifiers =============== */
    modifier directorExists {
        require(
            directors[msg.sender].shares > 0,
            'Boardroom: The director does not exist'
        );
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalShare() public view returns (uint256) {
        return boardHistory[boardHistory.length.sub(1)].totalShares;
    }

    function getShareOf(address director) public view returns (uint256) {
        return directors[director].shares;
    }

    function getAppointmentTimeOf(address director)
        public
        view
        returns (uint256)
    {
        return directors[director].appointmentTime;
    }

    function _getCashEarningsOf(address director, uint256 endSnapshotIndex, uint256 startSnapshopIndex) internal view returns (uint256) {
        uint256 startSnapshopIndextalRewards = 0;
        if (getShareOf(director) <= 0) {
            return startSnapshopIndextalRewards;
        }

        for (uint256 i = endSnapshotIndex; i > startSnapshopIndex; i = i.sub(1)) {
            BoardSnapshot memory snapshot = boardHistory[i.sub(1)];

            if (snapshot.timestamp < getAppointmentTimeOf(director)) {
                break;
            }

            uint256 snapshotRewards = snapshot
                .rewardReceived
                .mul(getShareOf(director))
                .div(snapshot.totalShares);
            startSnapshopIndextalRewards = startSnapshopIndextalRewards.add(snapshotRewards);
        }
        return startSnapshopIndextalRewards;
    }

    function getCashEarningsOfWithRange(address director, uint endSnapshotIndex, uint startSnapshopIndex) public view returns (uint256) {
        return _getCashEarningsOf(director, endSnapshotIndex, startSnapshopIndex);
    }
    
    function getCashEarningsOf(address director) public view returns (uint256) {
        // get cash earnings for the last DEFAULT_MAX_CLAIM_SNAPSHOTS snapshots by default
        uint256 endSnapshotIndex = boardHistory.length;
        uint256 startSnapshopIndex = endSnapshotIndex > DEFAULT_MAX_CLAIM_SNAPSHOTS ? endSnapshotIndex.sub(DEFAULT_MAX_CLAIM_SNAPSHOTS) : 0;
        return _getCashEarningsOf(director, endSnapshotIndex, startSnapshopIndex);
    }
    
    /* ========== MUTATIVE FUNCTIONS ========== */
    function _claimDividends(uint endSnapshotIndex, uint startSnapshopIndex) internal onlyOneBlock {
        uint256 totalRewards = _getCashEarningsOf(msg.sender, endSnapshotIndex, startSnapshopIndex);
        directors[msg.sender].appointmentTime = now;

        if (totalRewards > 0) {
            cash.safeTransfer(msg.sender, totalRewards);
            emit RewardPaid(msg.sender, totalRewards);
        }
    }

    function claimDividendsWithRange(uint256 endSnapshotIndex, uint256 startSnapshopIndex) public {
        _claimDividends(endSnapshotIndex, startSnapshopIndex);
    }
    
    function claimDividends() public {
        // claim dividents for the last DEFAULT_MAX_CLAIM_SNAPSHOTS snapshots by default      
        uint256 endSnapshotIndex = boardHistory.length;
        uint256 startSnapshopIndex = endSnapshotIndex > DEFAULT_MAX_CLAIM_SNAPSHOTS ? endSnapshotIndex.sub(DEFAULT_MAX_CLAIM_SNAPSHOTS) : 0;      
        _claimDividends(endSnapshotIndex, startSnapshopIndex);
    }

    function stake(uint256 amount) external {
        require(amount > 0, 'Boardroom: Cannot stake 0');

        // Claim all outstanding dividends before making state changes
        claimDividends();

        // Update director's boardseat
        Boardseat memory director = directors[msg.sender];
        director.shares = director.shares.add(amount);
        directors[msg.sender] = director;

        // Update latest snapshot
        uint256 snapshotIndex = boardHistory.length.sub(1);
        boardHistory[snapshotIndex].totalShares = totalShare().add(amount);

        share.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public directorExists {
        require(amount > 0, 'Boardroom: Cannot withdraw 0');

        // Claim all outstanding dividends before making state changes
        claimDividends();

        // Update director's boardseat
        uint256 directorShare = getShareOf(msg.sender);
        require(
            directorShare >= amount,
            'Boardroom: withdraw request greater than staked amount'
        );
        directors[msg.sender].shares = directorShare.sub(amount);

        // Update latest snapshot
        uint256 snapshotIndex = boardHistory.length.sub(1);
        boardHistory[snapshotIndex].totalShares = totalShare().sub(amount);

        share.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(getShareOf(msg.sender));
    }

    function allocateSeigniorage(uint256 amount)
        external
        onlyOneBlock
        onlyOperator
    {
        require(amount > 0, 'Boardroom: Cannot allocate 0');

        // Create & add new snapshot
        BoardSnapshot memory newSnapshot = BoardSnapshot({
            timestamp: now,
            rewardReceived: amount,
            totalShares: totalShare()
        });
        boardHistory.push(newSnapshot);

        cash.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardAdded(msg.sender, amount);
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
}
