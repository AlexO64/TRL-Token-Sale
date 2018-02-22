pragma solidity ^0.4.20; 

contract ERC20Interface {
    function totalSupply() public constant returns (uint256);
    function balanceOf(address owner) public constant returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);
    function allowance(address owner, address spender) public constant returns (uint256);
}

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------

interface ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token) external;
}

contract TRLCoinSale is ApproveAndCallFallBack {
    // Information about a single period
    struct Period {
        uint start;
        uint end;
        uint priceInWei;
        uint tokens;
    }

    // Information about a presale bonuses    
    struct Bonus {
        uint amount;
        uint8 bonus;
    }

    // Information about payment contribution
    struct PaymentContribution {
        uint weiContributed;
        uint timeContribution;
        uint receiveTokens;
    }

    struct TotalContribution {
        // total value of contribution
        uint totalReceiveTokens;
        // for empty address in mapping the value is 0 - otherwise we set it up 1
        uint8 active;
        // Only necessary if users want to be able to see contribution history. 
        // Otherwise, technically not necessary for the purposes of the sale
        PaymentContribution[] paymentHistory; 
    }

    // Some constant about our expected token distribution
    uint public constant TRLCOIN_DECIMALS = 0;
    uint public constant TOTAL_TOKENS_TO_DISTRIBUTE = 800000000 * (10 ** TRLCOIN_DECIMALS); // 800000000  TRL Token for distribution
    uint public constant TOTAL_TOKENS_AVAILABLE = 1000000000 * (10 ** TRLCOIN_DECIMALS);    // 1000000000 TRL Token totals

    address private owner;  // The owner of the crowdsale
    bool private hasStarted; // Has the crowdsale started?
    Period private preSale; // The configured periods for this crowdsale
    Period private sale;    // The configured periods for this crowdsale
    uint private distributionTime; // time after we could start distribution tokens
    
    Bonus private smallBonus; //The small bonus for presale
    Bonus private largeBonus; //The large bonus for presale

    uint private tokensRemainingForSale; //Remaining total amout of tokens  
    uint private tokensAwardedForSale;   // total awarded tokens

    // pair fo variables one for mapping one for iteration
    mapping(address => TotalContribution) public payments; // The configured periods for this crowdsale  
    address[] public paymentAddresses;

    // ERC20 Contract address.
    ERC20Interface private tokenWallet; // The token wallet contract used for this crowdsale
    
    // Fired once the transfer tokens to contract was successfull
    event Transfer(address to, uint amount);

    // Fired once the sale starts
    event Start(uint timestamp);

    // Fired whenever a contribution is made
    event Contribution(address indexed from, uint weiContributed, uint tokensReceived);

    // Fires whenever we send token to contributor
    event Distribute( address indexed to, uint tokensSend );

    function addContribution(address from, uint weiContributed, uint tokensReceived) private returns(bool) {
        //new contibutor
        require(weiContributed > 0);
        require(tokensReceived > 0);
        
        PaymentContribution memory newContribution;
        newContribution.timeContribution = block.timestamp;
        newContribution.weiContributed = weiContributed;
        newContribution.receiveTokens = tokensReceived;

        if (payments[from].active == 0) {
            // new total contribution           
            payments[from].totalReceiveTokens = tokensReceived;
            payments[from].active = 1;
            payments[from].paymentHistory.push(newContribution);
            
             // push new address to array for iteration by address  during distirbution process
            paymentAddresses.push(from);
        } else {
            payments[from].totalReceiveTokens += tokensReceived;
            payments[from].paymentHistory.push(newContribution);
        }
        return true;
    }

    // public getters for private state variables
    function getOwner() public view returns (address) { return owner; }
    function getHasStartedState() public view  returns(bool) { return hasStarted; }
    function getPresale() public view returns(uint, uint, uint, uint) { 
        return (preSale.start, preSale.end, preSale.priceInWei, preSale.tokens);
    }
    function getSale() public view returns(uint, uint, uint, uint) { 
        return (sale.start, sale.end, sale.priceInWei, sale.tokens);
    }
    function getDistributionTime() public view returns(uint) { return distributionTime; }
    
    function getSmallBonus() public view returns(uint, uint8) { return (smallBonus.amount, smallBonus.bonus ); }
    function getLargeBonus() public view returns(uint, uint8) { return (largeBonus.amount, largeBonus.bonus ); }
    function getTokenRemaining() public view returns(uint) { return tokensRemainingForSale; }
    function getTokenAwarded() public view returns(uint) { return tokensAwardedForSale; }

    function receiveApproval(address from, uint256 tokens, address token) external {
        require(hasStarted == false);
        tokensRemainingForSale += tokens;
        ERC20Interface(token).transferFrom(from, this, tokens);
    }

    function TRLCoinSale(address walletAddress) public {
        // Setup the owner and wallet
        owner = msg.sender;
        tokenWallet = ERC20Interface(walletAddress);

        // Make sure the provided token has the expected number of tokens to distribute
        require(tokenWallet.totalSupply() == TOTAL_TOKENS_AVAILABLE);

        // Make sure the owner actually controls all the tokens
        require(tokenWallet.balanceOf(owner) >= TOTAL_TOKENS_TO_DISTRIBUTE);

        // The multiplier necessary to change a coin amount to the token amount
        uint coinToTokenFactor = 10 ** TRLCOIN_DECIMALS;

        preSale.start = 1523318400; // 00:00:00, April 12, 2018 UTC use next site https://www.epochconverter.com/
        preSale.end = 1531353599; // 23:59:59, July 11, 2017 UTC
        preSale.priceInWei = (1 ether) / (20000 * coinToTokenFactor); // 1 ETH = 20000 TRL
        preSale.tokens = TOTAL_TOKENS_TO_DISTRIBUTE / 2;
       
        smallBonus.amount = ( 50 ether);
        smallBonus.bonus = 10;

        largeBonus.amount = ( 100 ether );
        largeBonus.bonus = 20;
    
        sale.start = 1531353600; // 00:00:00, July 12, 2018 UTC use next site https://www.epochconverter.com/
        sale.end = 1539302399; // 23:59:59, October 11, 2017 UTC
        sale.priceInWei = (1 ether) / (10000 * coinToTokenFactor); // 1 ETH = 20000 TRL
        sale.tokens = TOTAL_TOKENS_TO_DISTRIBUTE / 2;
        
        distributionTime = 1539302400;

        tokensRemainingForSale = 0;
        tokensAwardedForSale = 0;
    }

    // change default presale dates 
    function setPresaleDates(uint startDate, uint stopDate) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        //insanity check start < stop and stop resale < start of sale
        require(startDate < stopDate && stopDate < sale.start);
        
        preSale.start = startDate;
        preSale.end = stopDate;
    }

    // change default sale dates 
    function setSale(uint startDate, uint stopDate) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        // insanity check start < stop and stop resale < start of sale
        require(startDate < stopDate && startDate > preSale.end);
        // insanity check sale.end < distirbution token time
        require(sale.end < distributionTime);
        
        sale.start = startDate;
        sale.end = stopDate;
    }

    // change default distibution time
    function setDistributionTime(uint timeOfDistribution) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        // insanity check sale.end < distirbution token time
        require(sale.end < timeOfDistribution);
        
        distributionTime = timeOfDistribution;
    }

    // this function added Contributor that already made contribution before presale started 
    // should be called only after token was transfered to Sale contract
    function addContributorManually( address who, uint contributionWei, uint tokens) public {
        // only owner
        require(msg.sender == owner);   
        //contract must be not active
        require(hasStarted == false);
        // all entried must be added before presale started
        require(block.timestamp < preSale.start);
        // contract mush have total == TOTAL_TOKENS_TO_DISTRIBUTE
        require((tokensRemainingForSale + tokensAwardedForSale) == TOTAL_TOKENS_TO_DISTRIBUTE);

        addContribution(who, contributionWei, tokens);

        // decrement existing values
        // pair tokensRemainingForSale + tokensAwardedForSale always must be TOTAL_TOKENS_TO_DISTRIBUTE
        tokensRemainingForSale -= tokens;
        tokensAwardedForSale += tokens;
        preSale.tokens -= tokens;
    }

    // Start the crowdsale
    function startSale() public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot start if already started
        require(hasStarted == false);
        // Make sure the timestamps all make sense
        require(preSale.end > preSale.start);
        require(sale.end > sale.start);
        require(sale.start > preSale.end);
        require(distributionTime > sale.end);

        // Make sure the owner actually controls all the tokens for sales
        require(tokenWallet.balanceOf(owner) == TOTAL_TOKENS_TO_DISTRIBUTE);
        require((tokensRemainingForSale + tokensAwardedForSale) == TOTAL_TOKENS_TO_DISTRIBUTE);

        // Make sure we allocated all sale tokens
        require((preSale.tokens + sale.tokens) == tokensRemainingForSale);          

        // The sale can begin
        hasStarted = true;

        // Fire event that the sale has begun
        Start(block.timestamp);
    }    

    // Allow the current owner to change the owner of the crowdsale
    function changeOwner(address newOwner) public {
        // Only the owner can do this
        require(msg.sender == owner);

        // Change the owner
        owner = newOwner;
    }

    function preSaleFinishedProcess( uint timeOfRequest) private returns(bool) {
        // if we have Sales event and tokens of presale is not 0 move them to sales
        require(timeOfRequest >= sale.start && timeOfRequest <= sale.end);
        if (preSale.tokens != 0) {
            uint savePreSaleTomens = preSale.tokens;
            preSale.tokens = 0;
            sale.tokens += savePreSaleTomens;
        }
        return true;
    }
    
    // Calculate how many tokens can be distributed for the given contribution
    function getTokensForContribution(uint weiContribution) private returns(uint timeOfRequest, uint tokenAmount, uint weiRemainder, uint bonus) { 
        // Get curent time
        timeOfRequest = block.timestamp;
        
        // checking what perios are we
        if (timeOfRequest <= preSale.end) {
            // Return the amount of tokens that can be purchased
            // And the amount of wei that would be left over
            tokenAmount = weiContribution / preSale.priceInWei;
            weiRemainder = weiContribution % preSale.priceInWei;
            // if presale - checking bonuses
            if (weiContribution >= largeBonus.amount) {
                bonus = ( tokenAmount * largeBonus.bonus ) / 100;
            } else {
                 if (weiContribution >= smallBonus.amount) {
                    bonus = ( tokenAmount * smallBonus.bonus ) / 100;
                 }
            }             
        } else {
            // if sales preiod just started - transsfer all remain form presail token to sale
            preSaleFinishedProcess(timeOfRequest);
            // Return the amount of tokens that can be purchased
            // And the amount of wei that would be left over
            tokenAmount = weiContribution / sale.priceInWei;
            weiRemainder = weiContribution % sale.priceInWei;
        } 
        return(timeOfRequest, tokenAmount, weiRemainder, bonus);
    }
    
    function()public payable {
        // Cannot contribute if the sale hasn't started
        require(hasStarted == true);
        require(block.timestamp >= preSale.start && block.timestamp <= sale.end); 
        
        uint timeOfRequest;
        uint tokenAmount;
        uint weiRemainder;
        uint bonus;
        // Calculate the tokens to be distributed based on the contribution amount
        (timeOfRequest, tokenAmount, weiRemainder, bonus) = getTokensForContribution(msg.value);

        // Need to contribute enough for at least 1 token
        require(tokensRemainingForSale >= tokenAmount + bonus);
        
        // Need to contribute enough for at least 1 token
        require(tokenAmount > 0);
        
        // Sanity check: make sure the remainder is less or equal to what was sent to us
        require(weiRemainder <= msg.value);

        // Make sure there are enough tokens left to buy
        if (timeOfRequest <= preSale.end) {
            require(tokenAmount <= preSale.tokens);
            require(bonus <= sale.tokens);
            preSale.tokens -= tokenAmount;
            sale.tokens -= bonus;
        } else {
            require(tokenAmount <= sale.tokens);
            sale.tokens -= tokenAmount;
        }

        // this pair always must be in sync
        tokensRemainingForSale = tokensRemainingForSale - tokenAmount - bonus;
        tokensAwardedForSale = tokensAwardedForSale + tokenAmount + bonus;
        
        
        // setup new contribution
        addContribution(msg.sender, msg.value - weiRemainder, tokenAmount + bonus);

        // Transfer the token amount from the crowd sale's token wallet to the
        // sender's token wallet
        owner.transfer(msg.value - weiRemainder);
        // Return the remainder to the sender
        msg.sender.transfer(weiRemainder);

        // Since we refunded the remainder, the actual contribution is the amount sent
        // minus the remainder
        
        // Record the event
        Contribution(msg.sender, msg.value - weiRemainder, tokenAmount + bonus);
    } 

    
    // Allow the owner to withdraw all the tokens remaining after the
    // crowdsale is over
    function withdrawTokensRemaining() public returns (bool) {
        // Only the owner can do this
        require(msg.sender == owner);
        // The crowsale must be over to perform this operation
        require(block.timestamp > sale.end);
        // Get the remaining tokens owned by the crowdsale
        uint tokens = tokensRemainingForSale;
        tokensRemainingForSale = 0;
        // Transfer them all to the owner
        tokenWallet.transfer(owner, tokens);
        return true;
    }

    // Allow the owner to withdraw all ether from the contract after the
    // crowdsale is over - we don't need this function - just in case
    function withdrawEtherRemaining() public returns (bool) {
        // Only the owner can do this
        require(msg.sender == owner);
        // The crowsale must be over to perform this operation
        require(block.timestamp > sale.end);

        // Transfer them all to the owner
        owner.transfer(this.balance);
        return true;
    }

    function transferTokensToContributor(uint idx) public returns (bool) {
        // number of available token should be > 0
        if (payments[paymentAddresses[idx]].totalReceiveTokens > 0) {
            // this is for race conditions               
            uint tokenToSend = payments[paymentAddresses[idx]].totalReceiveTokens;
            payments[paymentAddresses[idx]].totalReceiveTokens = 0;
            // Transfer them all to the owner
            tokenWallet.transfer(paymentAddresses[idx], tokenToSend);
            Distribute(paymentAddresses[idx], tokenToSend);
        }
        return true;

    }
    
    function ditributeTokensToContributor( uint startIndex, uint numberOfContributors )public returns (bool) {
        // this is regular check for this function
        require(msg.sender == owner);
        require(startIndex < paymentAddresses.length);
        uint len = paymentAddresses.length < startIndex + numberOfContributors? paymentAddresses.length : startIndex + numberOfContributors;
        for (uint i = startIndex; i < len; i++) {
            transferTokensToContributor(i);                    
        }
        return true;        
    }

    function ditributeAllTokensToContributor( )public returns (bool) {
        // this is regular check for this function
        require(msg.sender == owner);
        for (uint i = 0; i < paymentAddresses.length; i++) {
            transferTokensToContributor(i); 
        }
        return true;        
    }
}
