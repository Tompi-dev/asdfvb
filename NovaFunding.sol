// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./NovaCoin.sol";

/**
 * @title NovaFunding
 * @dev Crowdfunding platform with ERC-20 reward tokens, refunds, and pull-based creator withdrawals.
 * Campaign IDs start from 1.
 */
contract NovaFunding is NovaCoin {
    // ---------------------------------------------------------
    // Reentrancy guard (minimal, OZ-style pattern)
    // ---------------------------------------------------------
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "ReentrancyGuard: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ---------------------------------------------------------
    // Constants
    // ---------------------------------------------------------
    uint256 public constant REWARD_RATE = 100; // 100 NOVA per 1 ETH

    // ---------------------------------------------------------
    // Structs
    // ---------------------------------------------------------
    struct Campaign {
        uint256 id;
        address payable creator;
        string title;
        string description;
        uint256 goalAmount;
        uint256 deadline;
        uint256 amountRaised;
        bool finalized;
        bool goalReached;
        bool creatorWithdrawn;
        uint256 creatorWithdrawable;
        mapping(address => uint256) contributions;
    }

    // ---------------------------------------------------------
    // State
    // ---------------------------------------------------------
    uint256 public campaignCount;
    mapping(uint256 => Campaign) private campaigns;
    mapping(address => uint256[]) public userCampaigns;

    // ---------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------
    modifier validCampaign(uint256 _campaignId) {
        require(_campaignId > 0 && _campaignId <= campaignCount, "Invalid campaign ID");
        _;
    }

    // ---------------------------------------------------------
    // Events
    // ---------------------------------------------------------
    event CampaignCreated(
        uint256 indexed id,
        address indexed creator,
        string title,
        uint256 goalAmount,
        uint256 deadline
    );
    event ContributionMade(
        uint256 indexed id,
        address indexed contributor,
        uint256 amountWei,
        uint256 novaRewardWholeTokens
    );
    event Finalized(
        uint256 indexed id,
        uint256 totalRaised,
        bool goalReached
    );
    event Withdrawal(
        uint256 indexed id,
        address indexed creator,
        uint256 amount
    );
    event Refund(
        uint256 indexed id,
        address indexed contributor,
        uint256 amount
    );

    // ---------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------
    constructor() NovaCoin(1000000) {}

    // ---------------------------------------------------------
    // Campaign creation
    // ---------------------------------------------------------
    /**
     * @notice Backward-compatible function: duration is provided in DAYS.
     * @dev Internally converts to seconds.
     */
    function createCampaign(
        string memory _title,
        string memory _description,
        uint256 _goalAmount,
        uint256 _durationDays
    ) external returns (uint256) {
        return _createCampaign(_title, _description, _goalAmount, _durationDays * 1 days);
    }

    /**
     * @notice Preferred function: duration is provided in SECONDS.
     */
    function createCampaignSeconds(
        string memory _title,
        string memory _description,
        uint256 _goalAmount,
        uint256 _durationSeconds
    ) external returns (uint256) {
        return _createCampaign(_title, _description, _goalAmount, _durationSeconds);
    }

    function _createCampaign(
        string memory _title,
        string memory _description,
        uint256 _goalAmount,
        uint256 _durationSeconds
    ) internal returns (uint256) {
        require(bytes(_title).length > 0, "Title required");
        require(_goalAmount > 0, "Goal must be > 0");
        require(_durationSeconds > 0, "Duration must be > 0");

        campaignCount++;
        uint256 newId = campaignCount;
        Campaign storage c = campaigns[newId];
        c.id = newId;
        c.creator = payable(msg.sender);
        c.title = _title;
        c.description = _description;
        c.goalAmount = _goalAmount;
        c.deadline = block.timestamp + _durationSeconds;

        userCampaigns[msg.sender].push(newId);

        emit CampaignCreated(newId, msg.sender, _title, _goalAmount, c.deadline);
        return newId;
    }

    // ---------------------------------------------------------
    // Contributions
    // ---------------------------------------------------------
    function contribute(uint256 _campaignId)
        external
        payable
        validCampaign(_campaignId)
    {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp < c.deadline, "Campaign has ended");
        require(!c.finalized, "Campaign already finalized");
        require(msg.value > 0, "Amount must be > 0");

        // Effects
        c.contributions[msg.sender] += msg.value;
        c.amountRaised += msg.value;

        // Reward logic (keep 100 NOVA per 1 ETH)
        uint256 rewardWholeTokens = (msg.value * REWARD_RATE) / 1 ether;
        if (rewardWholeTokens > 0) {
            mint(msg.sender, rewardWholeTokens * (10 ** uint256(decimals)));
        }

        emit ContributionMade(_campaignId, msg.sender, msg.value, rewardWholeTokens);
    }

    // ---------------------------------------------------------
    // Finalization + creator withdrawal (pull-payment)
    // ---------------------------------------------------------
    /**
     * @notice Anyone can finalize after deadline.
     * @dev If goal reached, marks creatorWithdrawable (no transfer here).
     */
    function finalizeCampaign(uint256 _campaignId)
        public
        validCampaign(_campaignId)
    {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp >= c.deadline, "Campaign still active");
        require(!c.finalized, "Already finalized");

        // Effects
        c.finalized = true;
        c.goalReached = c.amountRaised >= c.goalAmount;
        if (c.goalReached) {
            c.creatorWithdrawable = c.amountRaised;
        }

        emit Finalized(_campaignId, c.amountRaised, c.goalReached);
    }

    /**
     * @notice Creator withdraws raised funds after successful finalization.
     * @dev Double withdrawal is prevented by zeroing withdrawable + creatorWithdrawn flag.
     */
    function withdraw(uint256 _campaignId)
        external
        nonReentrant
        validCampaign(_campaignId)
    {
        Campaign storage c = campaigns[_campaignId];
        require(msg.sender == c.creator, "Only creator");
        require(c.finalized, "Campaign not finalized");
        require(c.goalReached, "Goal not reached");
        require(!c.creatorWithdrawn, "Already withdrawn");

        uint256 amount = c.creatorWithdrawable;
        require(amount > 0, "Nothing to withdraw");

        // Effects
        c.creatorWithdrawable = 0;
        c.creatorWithdrawn = true;

        // Interaction
        (bool ok, ) = c.creator.call{value: amount}("");
        require(ok, "Withdraw transfer failed");

        emit Withdrawal(_campaignId, c.creator, amount);
    }

    // ---------------------------------------------------------
    // Refunds
    // ---------------------------------------------------------
    /**
     * @notice Contributor refund if campaign failed.
     * Rules: deadline passed AND finalized AND goal NOT reached.
     */
    function refund(uint256 _campaignId)
        external
        nonReentrant
        validCampaign(_campaignId)
    {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp >= c.deadline, "Campaign still active");
        require(c.finalized, "Campaign not finalized");
        require(!c.goalReached, "Goal reached, no refunds");

        uint256 contributed = c.contributions[msg.sender];
        require(contributed > 0, "Nothing to refund");

        // Effects (prevents double refund + CEI)
        c.contributions[msg.sender] = 0;

        // Interaction
        (bool ok, ) = payable(msg.sender).call{value: contributed}("");
        require(ok, "Refund transfer failed");

        emit Refund(_campaignId, msg.sender, contributed);
    }

    // ---------------------------------------------------------
    // Views
    // ---------------------------------------------------------
    /**
     * @notice Campaign info without mapping to avoid mapping-in-struct return issues.
     */
    function getCampaignDetails(uint256 _campaignId)
        public
        view
        validCampaign(_campaignId)
        returns (
            uint256 id,
            address creator,
            string memory title,
            string memory description,
            uint256 goalAmount,
            uint256 deadline,
            uint256 amountRaised,
            bool finalized,
            bool goalReached,
            bool creatorWithdrawn,
            uint256 creatorWithdrawable
        )
    {
        Campaign storage c = campaigns[_campaignId];
        return (
            c.id,
            c.creator,
            c.title,
            c.description,
            c.goalAmount,
            c.deadline,
            c.amountRaised,
            c.finalized,
            c.goalReached,
            c.creatorWithdrawn,
            c.creatorWithdrawable
        );
    }

    /**
     * @notice Individual contribution tracking per campaign.
     */
    function getUserContribution(uint256 _campaignId, address _user)
        public
        view
        validCampaign(_campaignId)
        returns (uint256)
    {
        return campaigns[_campaignId].contributions[_user];
    }

    function getUserCampaigns(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userCampaigns[_user];
    }

    function canFinalize(uint256 _campaignId)
        external
        view
        validCampaign(_campaignId)
        returns (bool)
    {
        Campaign storage c = campaigns[_campaignId];
        return !c.finalized && block.timestamp >= c.deadline;
    }

    function canRefund(uint256 _campaignId, address _user)
        external
        view
        validCampaign(_campaignId)
        returns (bool)
    {
        Campaign storage c = campaigns[_campaignId];
        return
            c.finalized &&
            block.timestamp >= c.deadline &&
            !c.goalReached &&
            c.contributions[_user] > 0;
    }

    function canWithdraw(uint256 _campaignId, address _user)
        external
        view
        validCampaign(_campaignId)
        returns (bool)
    {
        Campaign storage c = campaigns[_campaignId];
        return
            _user == c.creator &&
            c.finalized &&
            c.goalReached &&
            !c.creatorWithdrawn &&
            c.creatorWithdrawable > 0;
    }

    function estimateReward(uint256 _weiAmount) external view returns (uint256) {
        uint256 rewardWholeTokens = (_weiAmount * REWARD_RATE) / 1 ether;
        return rewardWholeTokens * (10 ** uint256(decimals));
    }

    function getTimeLeft(uint256 _campaignId)
        external
        view
        validCampaign(_campaignId)
        returns (uint256)
    {
        Campaign storage c = campaigns[_campaignId];
        if (block.timestamp >= c.deadline) {
            return 0;
        }
        return c.deadline - block.timestamp;
    }

    function getProgressBps(uint256 _campaignId)
        external
        view
        validCampaign(_campaignId)
        returns (uint256)
    {
        Campaign storage c = campaigns[_campaignId];
        if (c.goalAmount == 0) {
            return 0;
        }
        return (c.amountRaised * 10000) / c.goalAmount;
    }
}
