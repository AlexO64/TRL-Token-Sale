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
        uint bonus;
        uint tokensAvailable;
    }

    // Information about payment contribution
    struct PaymentContribution {
        uint weiContributed;
        uint timeContribution;
        uint receiveTokens;
    }

    struct TotalContribution {
        // total value of contribution;
        // for empty address it will be zero
        uint totalReceiveTokens;
        // Only necessary if users want to be able to see contribution history. 
        // Otherwise, technically not necessary for the purposes of the sale
        PaymentContribution[] paymentHistory; 
    }

    // Some constant about our expected token distribution
    uint public constant TRLCOIN_DECIMALS = 0;
    uint public constant TOTAL_TOKENS_TO_DISTRIBUTE = 800000000 * (10 ** TRLCOIN_DECIMALS); // 800000000  TRL Token for distribution
    uint public constant TOTAL_TOKENS_AVAILABLE = 1000000000 * (10 ** TRLCOIN_DECIMALS);    // 1000000000 TRL Token totals

    // ERC20 Contract address.
    ERC20Interface private tokenWallet; // The token wallet contract used for this crowdsale
    
    uint private tokensRemainingForSale; //Remaining total amout of tokens  
    uint private tokensAwardedForSale;   // total awarded tokens
    
    address private owner;      // The owner of the crowdsale
    
    uint private distributionTime; // time after we could start distribution tokens
    
    Period private preSale20;   // The configured periods for this crowdsale
    Period private preSale10;   // The configured periods for this crowdsale
    Period private sale;        // The configured periods for this crowdsale
    
    // pair fo variables one for mapping one for iteration
    mapping(address => TotalContribution) public payments; // Track contributions by each address 
    address[] public paymentAddresses;

    bool private hasStarted;    // Has the crowdsale started?
    
    // Fired once the transfer tokens to contract was successfull
    event Transfer(address indexed to, uint amount);

    // Fired once the sale starts
    event Start(uint timestamp);

    // Fired whenever a contribution is made
    event Contribute(address indexed from, uint weiContributed, uint tokensReceived);

    // Fires whenever we send token to contributor
    event Distribute( address indexed to, uint tokensSend );

    function addContribution(address from, uint weiContributed, uint tokensReceived) private returns(bool) {
        //new contibutor
        require(weiContributed > 0);
        require(tokensReceived > 0);
        require(tokensRemainingForSale >= tokensReceived);
        
        PaymentContribution memory newContribution;
        newContribution.timeContribution = block.timestamp;
        newContribution.weiContributed = weiContributed;
        newContribution.receiveTokens = tokensReceived;

        // Since we cannot contribute zero tokens, if totalReceiveTokens is zero,
        // then this is the first contribution for this address
        if (payments[from].totalReceiveTokens == 0) {
            // new total contribution           
            payments[from].totalReceiveTokens = tokensReceived;
            payments[from].paymentHistory.push(newContribution);
            
             // push new address to array for iteration by address  during distirbution process
            paymentAddresses.push(from);
        } else {
            payments[from].totalReceiveTokens += tokensReceived;
            payments[from].paymentHistory.push(newContribution);
        }
        tokensRemainingForSale -= tokensReceived;
        tokensAwardedForSale += tokensReceived;
        return true;
    }

    // public getters for private state variables
    function getOwner() public view returns (address) { return owner; }
    function getHasStartedState() public view  returns(bool) { return hasStarted; }
    function getPresale20() public view returns(uint, uint, uint, uint, uint) { 
        return (preSale20.start, preSale20.end, preSale20.priceInWei, preSale20.bonus, preSale10.tokensAvailable);
    }
    function getPresale10() public view returns(uint, uint, uint, uint, uint) { 
        return (preSale10.start, preSale10.end, preSale10.priceInWei, preSale10.bonus, preSale10.tokensAvailable);
    }
    function getSale() public view returns(uint, uint, uint, uint, uint) { 
        return (sale.start, sale.end, sale.priceInWei, sale.bonus, sale.tokensAvailable);
    }
    function getDistributionTime() public view returns(uint) { return distributionTime; }
    
    function getTokenRemaining() public view returns(uint) { return tokensRemainingForSale; }
    function getTokenAwarded() public view returns(uint) { return tokensAwardedForSale; }

    // After create sale contract first function should be approveAndCall on Token contract
    // with this contract as spender and TOTAL_TOKENS_TO_DISTRIBUTE for approval
    // this callback function called form Token contract after approve on Token contract
    // eventually tokensRemainingForSale = TOTAL_TOKENS_TO_DISTRIBUTE
    function receiveApproval(address from, uint256 tokens, address token) external {
        // make sure the sales was not started
        require(hasStarted == false);
        
        // make sure this token address matches our configured tokenWallet address
        require(token == address(tokenWallet)); 
        
        tokensRemainingForSale += tokens;
        bool result = tokenWallet.transferFrom(from, this, tokens);
        // Make sure transfer succeeded
        require(result == true);
        
        Transfer(address(this), tokens);
    }

    // contract constructor
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

        preSale20.start = 1523491200; // 00:00:00, April 12, 2018 UTC use next site https://www.epochconverter.com/
        preSale20.end = 1531353599; // 23:59:59, July 11, 2018 UTC
        preSale20.priceInWei = (1 ether) / (20000 * coinToTokenFactor); // 1 ETH = 20000 TRL
        preSale20.bonus = 20; // bonus = 20%
        preSale20.tokensAvailable = TOTAL_TOKENS_TO_DISTRIBUTE / 2;
       
        preSale10.start = 1523491200; // 00:00:00, April 12, 2018 UTC use next site https://www.epochconverter.com/
        preSale10.end = 1531353599; // 23:59:59, July 11, 2018 UTC
        preSale10.priceInWei = (1 ether) / (20000 * coinToTokenFactor); // 1 ETH = 20000 TRL
        preSale10.bonus = 10; // bonus = 10%
        preSale10.tokensAvailable = 0;
        
        sale.start = 1531353600; // 00:00:00, July 12, 2018 UTC use next site https://www.epochconverter.com/
        sale.end = 1539302399; // 23:59:59, October 11, 2018 UTC
        sale.priceInWei = (1 ether) / (10000 * coinToTokenFactor); // 1 ETH = 10000 TRL
        sale.bonus = 0; // bonus = 0%
        sale.tokensAvailable = TOTAL_TOKENS_TO_DISTRIBUTE / 2;
        
        distributionTime = 1539302400; // 00:00:00, October 12, 2018 UTC

        tokensRemainingForSale = 0;
        tokensAwardedForSale = 0;
    }

    // change default presale dates 
    function setPresale20Dates(uint startDate, uint stopDate) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        //insanity check start < stop and stop resale < start of sale
        require(startDate < stopDate && stopDate < preSale10.start);
        
        preSale20.start = startDate;
        preSale20.end = stopDate;
    }

    // change default presale dates 
    function setPresale10Dates(uint startDate, uint stopDate) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        //insanity check start < stop and stop resale < start of sale
        require(startDate < stopDate && preSale20.end < startDate && stopDate < sale.start );
        
        preSale10.start = startDate;
        preSale10.end = stopDate;
    }

    // change default sale dates 
    function setSale(uint startDate, uint stopDate) public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot change if already started
        require(hasStarted == false);
        // insanity check start < stop and stop resale < start of sale
        require(startDate < stopDate && startDate > preSale10.end);
        // insanity check sale.end < distirbution token time
        require(stopDate < distributionTime);
        
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
    function addContributorManually( address who, uint contributionWei, uint tokens) public returns(bool) {
        // only owner
        require(msg.sender == owner);   
        //contract must be not active
        require(hasStarted == false);
        // all entried must be added before presale started
        require(block.timestamp < preSale20.start);
        // contract mush have total == TOTAL_TOKENS_TO_DISTRIBUTE
        require((tokensRemainingForSale + tokensAwardedForSale) == TOTAL_TOKENS_TO_DISTRIBUTE);
        // contract mush have total == TOTAL_TOKENS_TO_DISTRIBUTE
        require(preSale20.tokensAvailable > tokens);
        
        // decrement presale - token for manual contibution should be taken from presale
        preSale20.tokensAvailable -= tokens;

        addContribution(who, contributionWei, tokens);
        Contribute(who, contributionWei, tokens);
        return true;
    }

    // Start the crowdsale
    function startSale() public {
        // Only the owner can do this
        require(msg.sender == owner); 
        // Cannot start if already started
        require(hasStarted == false);
        // Make sure the timestamps all make sense
        require(preSale20.end > preSale20.start);
        require(preSale10.end > preSale10.start);
        require(sale.end > sale.start);
        require(preSale10.start > preSale20.end);
        require(sale.start > preSale10.end);
        require(distributionTime > sale.end);

        // Make sure the owner actually controls all the tokens for sales
        require(tokenWallet.balanceOf(address(this)) == TOTAL_TOKENS_TO_DISTRIBUTE);
        require((tokensRemainingForSale + tokensAwardedForSale) == TOTAL_TOKENS_TO_DISTRIBUTE);

        // Make sure we allocated all sale tokens
        require((preSale20.tokensAvailable + sale.tokensAvailable) == tokensRemainingForSale);          

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

    // Calculate how many tokens can be distributed for the given contribution
    function getTokensForContribution(uint weiContribution) private returns(uint timeOfRequest, uint tokenAmount, uint weiRemainder, uint bonus) { 
        // Get curent time
        timeOfRequest = block.timestamp;
        // just for sure that bonus is initialized
        bonus = 0;
                 
        // checking what period are we
        if (timeOfRequest <= preSale20.end) {
            // Return the amount of tokens that can be purchased
            // And the amount of wei that would be left over
            tokenAmount = weiContribution / preSale20.priceInWei;
            weiRemainder = weiContribution % preSale20.priceInWei;
            bonus = ( tokenAmount * preSale20.bonus ) / 100;
            
            //withdraw token from corresponding sales part
            preSale20.tokensAvailable =- tokenAmount;
            sale.tokensAvailable =- bonus;
        } else {
            // move tokens form preSale20 to preSale10
            if (preSale20.tokensAvailable > 0 ){
                uint tokensMoveToPreSale10 = preSale20 .tokensAvailable;
                preSale20.tokensAvailable = 0;
                preSale10.tokensAvailable += tokensMoveToPreSale10;
            }
            if (timeOfRequest <= preSale10.end) {
                // Return the amount of tokens that can be purchased
                // And the amount of wei that would be left over
                tokenAmount = weiContribution / preSale10.priceInWei;
                weiRemainder = weiContribution % preSale10.priceInWei;
                bonus = ( tokenAmount * preSale10.bonus ) / 100;
                
                //withdraw token from corresponding sales part
                preSale10.tokensAvailable =- tokenAmount;
                sale.tokensAvailable =- bonus;
            }else{
                // move tokens form preSale10 to preSale10
                if (preSale10 .tokensAvailable > 0 ){
                    uint tokensMoveToSale = preSale10.tokensAvailable;
                    preSale10.tokensAvailable = 0;
                    sale.tokensAvailable += tokensMoveToSale;
                }
            
                // Return the amount of tokens that can be purchased
                // And the amount of wei that would be left over
                tokenAmount = weiContribution / sale.priceInWei;
                weiRemainder = weiContribution % sale.priceInWei;
                bonus = 0;
                
                //withdraw token from corresponding sales part
                sale.tokensAvailable =- tokenAmount;
            }
        } 
        return(timeOfRequest, tokenAmount, weiRemainder, bonus);
    }
    
    function()public payable {
        // Cannot contribute if the sale hasn't started
        require(hasStarted == true);
        // Cannot contribute if sale is not in this time range
        require((block.timestamp >= preSale20.start && block.timestamp <= preSale20.end)
            || (block.timestamp >= preSale10.start && block.timestamp <= preSale10.end)
        || (block.timestamp >= sale.start && block.timestamp <= sale.end) ); 

        // Cannot contribute if amount of money send is les then 0.1 ETH
        require(msg.value >= 100 finney);
        
        uint timeOfRequest;
        uint tokenAmount;
        uint weiRemainder;
        uint bonus;
        // Calculate the tokens to be distributed based on the contribution amount
        (timeOfRequest, tokenAmount, weiRemainder, bonus) = getTokensForContribution(msg.value);

        // Make sure there are enough tokens left to buy
        require(tokensRemainingForSale >= tokenAmount + bonus);
        
        // Need to contribute enough for at least 1 token
        require(tokenAmount > 0);
        
        // Sanity check: make sure the remainder is less or equal to what was sent to us
        require(weiRemainder <= msg.value);
        
        // setup new contribution
        addContribution(msg.sender, msg.value - weiRemainder, tokenAmount + bonus);

        /// Transfer contribution amount to owner
        owner.transfer(msg.value - weiRemainder);
        // Return the remainder to the sender
        msg.sender.transfer(weiRemainder);

        // Since we refunded the remainder, the actual contribution is the amount sent
        // minus the remainder
        
        // Record the event
        Contribute(msg.sender, msg.value - weiRemainder, tokenAmount + bonus);
    } 

    
    // Allow the owner to withdraw all the tokens remaining after the
    // crowdsale is over
    function withdrawTokensRemaining() public returns (bool) {
        // Only the owner can do this
        require(msg.sender == owner);
        // The crowsale must be over to perform this operation
        require(block.timestamp > sale.end);
        // Get the remaining tokens owned by the crowdsale
        uint tokenToSend = tokensRemainingForSale;
        // Set available tokens to Zero
        tokensRemainingForSale = 0;
        sale.tokensAvailable = 0;
        // Transfer them all to the owner
        bool result = tokenWallet.transfer(owner, tokenToSend);
        // Be sure that transfer was successfull
        require(result == true);
        Distribute(owner, tokenToSend);
        return true;
    }

    // Allow the owner to withdraw all ether from the contract after the crowdsale is over.
    // We don't need this function( we transfer ether immediately to owner - just in case
    function withdrawEtherRemaining() public returns (bool) {
        // Only the owner can do this
        require(msg.sender == owner);
        // The crowsale must be over to perform this operation
        require(block.timestamp > sale.end);

        // Transfer them all to the owner
        owner.transfer(this.balance);
        return true;
    }

    // this function is intentionally internal because we do not check conditions here
    function transferTokensToContributor(uint idx) private returns (bool) {
        if (payments[paymentAddresses[idx]].totalReceiveTokens > 0) {
            // this is for race conditions               
            uint tokenToSend = payments[paymentAddresses[idx]].totalReceiveTokens;
            payments[paymentAddresses[idx]].totalReceiveTokens = 0;
            
            //decrement awarded token
            require(tokensAwardedForSale >= tokenToSend);
            tokensAwardedForSale -= tokenToSend;
            // Transfer them all to the owner
            bool result = tokenWallet.transfer(paymentAddresses[idx], tokenToSend);
            // Be sure that transfer was successfull
            require(result == true);
            Distribute(paymentAddresses[idx], tokenToSend);
        }
        return true;

    }
    
    // get number of real contributors
    function getNumberOfContributors( ) public view returns (uint) {
        return paymentAddresses.length;
    }
    
    // This function for transfer tokens one by one
    function distributeTokensToContributorByIndex( uint indexVal) public returns (bool) {
        // this is regular check for this function
        require(msg.sender == owner);
        require(block.timestamp >= distributionTime);
        require(indexVal < paymentAddresses.length);
        
        transferTokensToContributor(indexVal);                    
        return true;        
    }

    function distributeTokensToContributor( uint startIndex, uint numberOfContributors )public returns (bool) {
        // this is regular check for this function
        require(msg.sender == owner);
        require(block.timestamp >= distributionTime);
        require(startIndex < paymentAddresses.length);
        
        uint len = paymentAddresses.length < startIndex + numberOfContributors? paymentAddresses.length : startIndex + numberOfContributors;
        for (uint i = startIndex; i < len; i++) {
            transferTokensToContributor(i);                    
        }
        return true;        
    }

    function distributeAllTokensToContributor( )public returns (bool) {
        // this is regular check for this function
        require(msg.sender == owner);
        require(block.timestamp >= distributionTime);
        
        for (uint i = 0; i < paymentAddresses.length; i++) {
            transferTokensToContributor(i); 
        }
        return true;        
    }
    
    // Owner can transfer out any accidentally sent ERC20 tokens as long as they are not the sale tokens
    function transferAnyERC20Token(address tokenAddress, uint tokens) public returns (bool) {
        require(msg.sender == owner);
        require(tokenAddress != address(tokenWallet));
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}
