/*

- Bytecode Verification performed was compared on second iteration -

This file is part of the HongCoin.

The HongCoin is free software: you can redistribute it and/or modify
it under the terms of the GNU lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

The HongCoin is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU lesser General Public License for more details.

You should have received a copy of the GNU lesser General Public License
along with the HongCoin.  If not, see <http://www.gnu.org/licenses/>.
*/



contract TokenInterface {
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    uint256 public totalSupply;

    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _amount) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _amount) returns (bool success);

    event evTransfer(address indexed _from, address indexed _to, uint256 _amount);
}


contract Token is TokenInterface {
    // Protects users by preventing the execution of method calls that
    // inadvertently also transferred ether
    modifier noEther() {if (msg.value > 0) throw; _}

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _amount) noEther returns (bool success) {
        if (balances[msg.sender] >= _amount && _amount > 0) {
            balances[msg.sender] -= _amount;
            balances[_to] += _amount;
            evTransfer(msg.sender, _to, _amount);
            return true;
        } else {
           return false;
        }
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) noEther returns (bool success) {

        if (balances[_from] >= _amount
            && allowed[_from][msg.sender] >= _amount
            && _amount > 0) {

            balances[_to] += _amount;
            balances[_from] -= _amount;
            allowed[_from][msg.sender] -= _amount;
            evTransfer(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }
}






contract ManagedAccountInterface {
    address public owner;
    bool public payOwnerOnly;
    uint public accumulatedInput;

    function payOut(address _recipient, uint _amount) returns (bool);

    event evPayOut(address indexed _recipient, uint _amount);
}


contract ManagedAccount is ManagedAccountInterface{

    function ManagedAccount(address _owner, bool _payOwnerOnly) {
        owner = _owner;
        payOwnerOnly = _payOwnerOnly;
    }

    function() {
        accumulatedInput += msg.value;
    }

    function payOut(address _recipient, uint _amount) returns (bool) {
        if (msg.sender != owner || msg.value > 0 || (payOwnerOnly && _recipient != owner))
            throw;
        if (_recipient.call.value(_amount)()) {
            evPayOut(_recipient, _amount);
            return true;
        } else {
            return false;
        }
    }
}





/*
 * Token Creation contract, similar to other organization,for issuing tokens and initialize
 * its ether fund.
*/


contract TokenCreationInterface {

    uint public closingTime;
    uint public minTokensToCreate;
    bool public isFueled;
    address public privateCreation;
    ManagedAccount public extraBalance;
    mapping (address => uint256) weiGiven;

    function createTokenProxy(address _tokenHolder) returns (bool success);
    function refund();
    function divisor() constant returns (uint divisor);

    event evFuelingToDate(uint value);
    event evCreatedToken(address indexed to, uint amount);
    event evRefund(address indexed to, uint value);
}


contract TokenCreation is TokenCreationInterface, Token {
    function TokenCreation(
        uint _minTokensToCreate,
        uint _closingTime,
        address _privateCreation) {

        closingTime = _closingTime;
        minTokensToCreate = _minTokensToCreate;
        privateCreation = _privateCreation;
        extraBalance = new ManagedAccount(address(this), true);
    }

    function createTokenProxy(address _tokenHolder) returns (bool success) {
        if (now < closingTime && msg.value > 0
            && (privateCreation == 0 || privateCreation == msg.sender)) {

            uint token = (msg.value * 100) / divisor();
            extraBalance.call.value(msg.value - token)();
            balances[_tokenHolder] += token;
            totalSupply += token;
            weiGiven[_tokenHolder] += msg.value;
            evCreatedToken(_tokenHolder, token);
            if (totalSupply >= minTokensToCreate && !isFueled) {
                isFueled = true;
                evFuelingToDate(totalSupply);
            }
            return true;
        }
        throw;
    }

    function refund() noEther {
        if (now > closingTime && !isFueled) {
            // Get extraBalance - will only succeed when called for the first time
            if (extraBalance.balance >= extraBalance.accumulatedInput())
                extraBalance.payOut(address(this), extraBalance.accumulatedInput());

            // Execute refund
            if (msg.sender.call.value(weiGiven[msg.sender])()) {
                evRefund(msg.sender, weiGiven[msg.sender]);
                totalSupply -= balances[msg.sender];
                balances[msg.sender] = 0;
                weiGiven[msg.sender] = 0;
            }
        }
    }

    function divisor() constant returns (uint divisor) {

        // Quantity divisor model: based on total quantity of coins issued
        // Temp: Price ranged from 1.0 to 1.04 Ether for 500 M HongCoin Tokens

        // The number of (base unit) tokens per wei is calculated
        // as `msg.value` * 100 / `divisor`

        // TODO Fix the unit for totalSupply
        if(totalSupply < 1000000){
            return 100;
        } else if (totalSupply < 2000000){
            return 101;
        } else if (totalSupply < 3000000){
            return 102;
        } else if (totalSupply < 4000000){
            return 103;
        } else {
            return 104;
        }
    }
}





contract HongCoinInterface {

    // we do not have grace period. Once the goal is reached, the fund is secured


    // Proposals to spend the HongCoin's ether or to choose a new Curator
    Proposal[] public proposals;
    // The quorum needed for each proposal is partially calculated by
    // totalSupply / minQuorumDivisor
    uint public minQuorumDivisor;
    uint public lastTimeMinQuorumMet;

    address public curator;
    mapping (address => bool) public allowedRecipients;

    mapping (address => uint) public rewardToken;
    uint public totalRewardToken;

    ManagedAccount public rewardAccount;
    ManagedAccount public HongCoinRewardAccount;

    mapping (address => uint) public HongCoinPaidOut;
    mapping (address => uint) public paidOut;
    mapping (address => uint) public blocked;

    // uint public proposalDeposit;
    // uint sumOfProposalDeposits;

    HongCoin_Creator public hongcoinCreator;


    // TODO remove the proposal part

    // A proposal with `newCurator == false` represents a transaction
    // to be issued by this HongCoin
    // A proposal with `newCurator == true` represents a HongCoin split
    struct Proposal {
        // The address where the `amount` will go to if the proposal is accepted
        // or if `newCurator` is true, the proposed Curator of
        // the new HongCoin).
        address recipient;
        // The amount to transfer to `recipient` if the proposal is accepted.
        uint amount;
        // A plain text description of the proposal
        string description;
        // A unix timestamp, denoting the end of the voting period
        uint votingDeadline;
        // True if the proposal's votes have yet to be counted, otherwise False
        bool open;
        // True if quorum has been reached, the votes have been counted, and
        // the majority said yes
        bool proposalPassed;
        // A hash to check validity of a proposal
        bytes32 proposalHash;
        // Deposit in wei the creator added when submitting their proposal. It
        // is taken from the msg.value of a newProposal call.
        // uint proposalDeposit;
        // True if this proposal is to assign a new Curator
        bool newCurator;
        // Data needed for splitting the HongCoin
        SplitData[] splitData;
        // Number of Tokens in favor of the proposal
        uint yea;
        // Number of Tokens opposed to the proposal
        uint nay;
        // Simple mapping to check if a shareholder has voted for it
        mapping (address => bool) votedYes;
        // Simple mapping to check if a shareholder has voted against it
        mapping (address => bool) votedNo;
        // Address of the shareholder who created the proposal
        address creator;
    }

    // Used only in the case of a newCurator proposal.
    struct SplitData {
        uint splitBalance;
        uint totalSupply;
        uint rewardToken;
        HongCoin newHongCoin;
    }

    // Used to restrict access to certain functions to only HongCoin Token Holders
    modifier onlyTokenholders {}

    function () returns (bool success);
    function receiveEther() returns(bool);

    // function newProposal(
    //     address _recipient,
    //     uint _amount,
    //     string _description,
    //     bytes _transactionData,
    //     uint _debatingPeriod,
    //     bool _newCurator
    // ) onlyTokenholders returns (uint _proposalID);

    function executeProject(
        address _projectWallet,
        uint _amount
    ) returns (bool _success);

    function changeAllowedRecipients(address _recipient, bool _allowed) external returns (bool _success);
    function retrieveHongCoinReward(bool _toMembers) external returns (bool _success);
    function getMyReward() returns(bool _success);
    function withdrawRewardFor(address _account) internal returns (bool _success);
    function transferWithoutReward(address _to, uint256 _amount) returns (bool success);
    function transferFromWithoutReward(
        address _from,
        address _to,
        uint256 _amount
    ) returns (bool success);
    function isBlocked(address _account) internal returns (bool);
    function unblockMe() returns (bool);

    event evProjectExecuted(address _projectWallet, uint _amount, bool result);
    event evNewCurator(address indexed _newCurator);
    event evAllowedRecipientChanged(address indexed _recipient, bool _allowed);
}

// The HongCoin contract itself
contract HongCoin is HongCoinInterface, Token, TokenCreation {

    // Modifier that allows only shareholders to vote and create new proposals
    modifier onlyTokenholders {
        if (balanceOf(msg.sender) == 0) throw;
            _
    }

    function HongCoin(
        address _curator,
        HongCoin_Creator _hongcoinCreator,
        // uint _proposalDeposit,
        uint _minTokensToCreate,
        uint _closingTime,
        address _privateCreation
    ) TokenCreation(_minTokensToCreate, _closingTime, _privateCreation) {

        curator = _curator;
        hongcoinCreator = _hongcoinCreator;
        // proposalDeposit = _proposalDeposit;
        rewardAccount = new ManagedAccount(address(this), false);
        HongCoinRewardAccount = new ManagedAccount(address(this), false);
        if (address(rewardAccount) == 0)
            throw;
        if (address(HongCoinRewardAccount) == 0)
            throw;
        lastTimeMinQuorumMet = now;
        minQuorumDivisor = 5; // sets the minimal quorum to 20%
        proposals.length = 1; // avoids a proposal with ID 0 because it is used

        allowedRecipients[address(this)] = true;
        allowedRecipients[curator] = true;
    }

    function () returns (bool success) {
        // if condition met, we accept HongCoin purchases
        if (!isFueled && msg.sender != address(extraBalance))
            return createTokenProxy(msg.sender);
        else
            return receiveEther();
    }


    function receiveEther() returns (bool) {
        return true;
    }



    function executeProject(
        address _projectWallet,
        uint _amount
    ) noEther returns (bool _success) {

        bool proposalCheck = true;

        if (_amount > actualBalance())
            proposalCheck = false;

        _success = true;

        // only create reward tokens when ether is not sent to the HongCoin itself and
        // related addresses. Proxy addresses should be forbidden by the curator.
        if (_projectWallet != address(this) && _projectWallet != address(rewardAccount)
            && _projectWallet != address(HongCoinRewardAccount)
            && _projectWallet != address(extraBalance)
            && _projectWallet != address(curator)) {

            rewardToken[address(this)] += _amount;
            totalRewardToken += _amount;
        }

        // Initiate event
        evProjectExecuted(_projectWallet, _amount, _success);
    }


    function retrieveHongCoinReward(bool _toMembers) external noEther returns (bool _success) {
        HongCoin hongcoin = HongCoin(msg.sender);

        if ((rewardToken[msg.sender] * HongCoinRewardAccount.accumulatedInput()) /
            totalRewardToken < HongCoinPaidOut[msg.sender])
            throw;

        uint reward =
            (rewardToken[msg.sender] * HongCoinRewardAccount.accumulatedInput()) /
            totalRewardToken - HongCoinPaidOut[msg.sender];
        if(_toMembers) {
            if (!HongCoinRewardAccount.payOut(hongcoin.rewardAccount(), reward))
                throw;
            }
        else {
            if (!HongCoinRewardAccount.payOut(hongcoin, reward))
                throw;
        }
        HongCoinPaidOut[msg.sender] += reward;
        return true;
    }

    function getMyReward() noEther returns (bool _success) {
        return withdrawRewardFor(msg.sender);
    }


    function withdrawRewardFor(address _account) noEther internal returns (bool _success) {
        if ((balanceOf(_account) * rewardAccount.accumulatedInput()) / totalSupply < paidOut[_account])
            throw;

        uint reward =
            (balanceOf(_account) * rewardAccount.accumulatedInput()) / totalSupply - paidOut[_account];
        if (!rewardAccount.payOut(_account, reward))
            throw;
        paidOut[_account] += reward;
        return true;
    }


    function transfer(address _to, uint256 _value) returns (bool success) {
        if (isFueled
            && now > closingTime
            && !isBlocked(msg.sender)
            && transferPaidOut(msg.sender, _to, _value)
            && super.transfer(_to, _value)) {

            return true;
        } else {
            throw;
        }
    }


    function transferWithoutReward(address _to, uint256 _value) returns (bool success) {
        if (!getMyReward())
            throw;
        return transfer(_to, _value);
    }


    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (isFueled
            && now > closingTime
            && !isBlocked(_from)
            && transferPaidOut(_from, _to, _value)
            && super.transferFrom(_from, _to, _value)) {

            return true;
        } else {
            throw;
        }
    }


    function transferFromWithoutReward(
        address _from,
        address _to,
        uint256 _value
    ) returns (bool success) {

        if (!withdrawRewardFor(_from))
            throw;
        return transferFrom(_from, _to, _value);
    }


    function transferPaidOut(
        address _from,
        address _to,
        uint256 _value
    ) internal returns (bool success) {

        uint transferPaidOut = paidOut[_from] * _value / balanceOf(_from);
        if (transferPaidOut > paidOut[_from])
            throw;
        paidOut[_from] -= transferPaidOut;
        paidOut[_to] += transferPaidOut;
        return true;
    }


    function changeAllowedRecipients(address _recipient, bool _allowed) noEther external returns (bool _success) {
        if (msg.sender != curator)
            throw;
        allowedRecipients[_recipient] = _allowed;
        evAllowedRecipientChanged(_recipient, _allowed);
        return true;
    }


    function isRecipientAllowed(address _recipient) internal returns (bool _isAllowed) {
        if (allowedRecipients[_recipient]
            || (_recipient == address(extraBalance)
                // only allowed when at least the amount held in the
                // extraBalance account has been spent from the HongCoin
                && totalRewardToken > extraBalance.accumulatedInput()))
            return true;
        else
            return false;
    }

    function actualBalance() constant returns (uint _actualBalance) {
        // return this.balance - sumOfProposalDeposits;
        return this.balance;
    }



    function isBlocked(address _account) internal returns (bool) {
        if (blocked[_account] == 0)
            return false;
        Proposal p = proposals[blocked[_account]];
        if (now > p.votingDeadline) {
            blocked[_account] = 0;
            return false;
        } else {
            return true;
        }
    }

    function unblockMe() returns (bool) {
        return isBlocked(msg.sender);
    }
}

contract HongCoin_Creator {
    function createHongCoin(
        address _curator,
        // uint _proposalDeposit,
        uint _minTokensToCreate,
        uint _closingTime
    ) returns (HongCoin _newHongCoin) {

        return new HongCoin(
            _curator,
            HongCoin_Creator(this),
            // _proposalDeposit,
            _minTokensToCreate,
            _closingTime,
            msg.sender
        );
    }
}


contract GovernanceInterface {
    // define the governance of this organization and critical functions
    function kickoff(uint _fiscal) returns (bool);
    function reserveToWallet() returns (bool);
    function issueManagementFee() returns (bool);
    function harvest() returns (bool);
    function freezeFund() returns (bool);
    function unFreezeFund() returns (bool);
    function investProject(address _projectWallet) returns (bool);

    event evKickoff(uint256 _fiscal);
    event evIssueManagementFee();
    event evFreezeFund();
    event evUnFreezeFund();
}


contract Governance is GovernanceInterface {
    modifier noEther() {if (msg.value > 0) throw; _}

    function kickoff(
        uint256 _fiscal
    ) noEther returns (bool success) {
        evKickoff(_fiscal);
        return true;
    }

    function reserveToWallet(address _reservedWallet) returns (bool success) {
        // Send 8% for 4 years of Management fee to ReservedWallet
        return true;
    }
    function issueManagementFee() returns (bool success) {
        // Send 2% of Management fee from ReservedWallet
        return true;
    }

    function harvest() returns (bool success) {
        // harvest for every token owner
        return true;
    }

    function freezeFund() returns (bool success) {
        // freezeFund
        evFreezeFund();
        return true;
    }

    function unFreezeFund() returns (bool success) {
        // harvest for every token owner
        evUnFreezeFund();
        return true;
    }

    function investProject(
        address _projectWallet
    ) returns (bool success) {
        // start investing a project

        // send a fixed amount (1 barrel) to the project address

        return true;
    }
}
