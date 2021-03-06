// Copyright (C) 2020 Centrifuge

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.15 <0.6.0;

import "./base_system.sol";
import "./users/borrower.sol";
import "./users/admin.sol";

contract ScenarioTest is BaseSystemTest {
    Hevm public hevm;

    function setUp() public {
        baseSetup("whitelist", "default", false);
        createTestUsers(false);
        // setup hevm
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1234567);
    }

    // Checks
    function checkAfterBorrow(uint tokenId, uint tBalance) public {
        assertEq(currency.balanceOf(borrower_), tBalance);
        assertEq(collateralNFT.ownerOf(tokenId), address(shelf));
    }

    function checkAfterRepay(uint loan, uint tokenId, uint tTotal, uint tLender) public {
        assertEq(collateralNFT.ownerOf(tokenId), borrower_);
        assertEq(pile.debt(loan), 0);
        assertEq(currency.balanceOf(borrower_), safeSub(tTotal, tLender));
        assertEq(currency.balanceOf(address(pile)), 0);
    }

    function setupLoan(uint tokenId, address collateralNFT_, uint principal, uint rate) public returns (uint) {
        // define rate
        admin.doInitRate(rate, rate);
        // collateralNFT whitelist

        // borrower issue loans
        uint loan =  borrower.issue(collateralNFT_, tokenId);

        // admin define ceiling
        admin.setCeiling(loan, principal);

        // add rate for loan
        admin.doAddRate(loan, rate);
        return loan;
    }

    function borrow(uint loan, uint tokenId, uint principal) public {
        borrower.approveNFT(collateralNFT, address(shelf));
        setupCurrencyOnLender(principal);
        borrower.borrowAction(loan, principal);
        checkAfterBorrow(tokenId, principal);
    }

    function defaultLoan() public pure returns(uint principal, uint rate) {
        principal = 1000 ether;
        // define rate
        rate = uint(1000000564701133626865910626); // 5 % day

        return (principal, rate);
    }

    function setupOngoingLoan() public returns (uint loan, uint tokenId, uint principal, uint rate) {
        (principal, rate) = defaultLoan();
        // create borrower collateral collateralNFT
        tokenId = collateralNFT.issue(borrower_);
        loan = setupLoan(tokenId, collateralNFT_, principal, rate);
        borrow(loan, tokenId, principal);

        return (loan, tokenId, principal, rate);
    }

    function setupRepayReq() public returns(uint) {
        // borrower needs some currency to pay rate
        uint extra = 100000000000 ether;
        currency.mint(borrower_, extra);

        // allow pile full control over borrower tokens
        borrower.doApproveCurrency(address(shelf), uint(-1));

        return extra;
    }

    // note: this method will be refactored with the new lender side contracts, as the distributor should not hold any currency
    function currdistributorBal() public view returns(uint) {
        return currency.balanceOf(address(distributor));
    }

    function borrowRepay(uint principal, uint rate) public {
        CeilingLike ceiling_ = CeilingLike(address(ceiling));

        // create borrower collateral collateralNFT
        uint tokenId = collateralNFT.issue(borrower_);
        uint loan = setupLoan(tokenId, collateralNFT_, principal, rate);

        assertEq(ceiling_.ceiling(loan), principal);
        borrow(loan, tokenId, principal);
        assertEq(ceiling_.ceiling(loan), 0);

        hevm.warp(now + 10 days);

        // borrower needs some currency to pay rate
        setupRepayReq();
        uint distributorShould = pile.debt(loan) + currdistributorBal();
        // close without defined amount
        borrower.doClose(loan);
        uint totalT = uint(currency.totalSupply());
        checkAfterRepay(loan, tokenId, totalT, distributorShould);
    }

    // --- Tests ---


    function testBorrowTransaction() public {
        // collateralNFT value
        uint principal = 100;

        // create borrower collateral collateralNFT
        uint tokenId = collateralNFT.issue(borrower_);
        // borrower issue loan
        uint loan =  borrower.issue(collateralNFT_, tokenId);

        // admin define ceiling
        admin.setCeiling(loan, principal);
        borrower.approveNFT(collateralNFT, address(shelf));
        setupCurrencyOnLender(principal);
        borrower.borrowAction(loan, principal);
        checkAfterBorrow(tokenId, principal);
    }

    function testBorrowAndRepay() public {
        (uint principal, uint rate) = defaultLoan();
        borrowRepay(principal, rate);
    }


    function testMediumSizeLoans() public {
        (uint principal, uint rate) = defaultLoan();

        principal = 1000000 ether;

        borrowRepay(principal, rate);
    }

    function testHighSizeLoans() public {
        (uint principal, uint rate) = defaultLoan();
        principal = 100000000 ether; // 100 million

        borrowRepay(principal, rate);
    }

    function testRepayFullAmount() public {
        (uint loan, uint tokenId,,) = setupOngoingLoan();

        hevm.warp(now + 1 days);

        // borrower needs some currency to pay rate
        setupRepayReq();
        uint distributorShould = pile.debt(loan) + currdistributorBal();
        // close without defined amount
        borrower.doClose(loan);

        uint totalT = uint(currency.totalSupply());
        checkAfterRepay(loan, tokenId, totalT, distributorShould);
    }

    function testLongOngoing() public {
        (uint loan, uint tokenId, , ) = setupOngoingLoan();

        // interest 5% per day 1.05^300 ~ 2273996.1286 chi
        hevm.warp(now + 300 days);

        // borrower needs some currency to pay rate
        setupRepayReq();

        uint distributorShould = pile.debt(loan) + currdistributorBal();

        // close without defined amount
        borrower.doClose(loan);

        uint totalT = uint(currency.totalSupply());
        checkAfterRepay(loan, tokenId, totalT, distributorShould);
    }

    function testMultipleBorrowAndRepay () public {
        uint principal = 100;
        uint rate = uint(1000000564701133626865910626);

        uint tBorrower = 0;
        // borrow
        for (uint i = 1; i <= 10; i++) {

            principal = i * 80;

            // create borrower collateral collateralNFT
            uint tokenId = collateralNFT.issue(borrower_);
            // collateralNFT whitelist
            uint loan = setupLoan(tokenId, collateralNFT_, principal, rate);

            borrower.approveNFT(collateralNFT, address(shelf));

            setupCurrencyOnLender(principal);
            borrower.borrowAction(loan, principal);
            tBorrower += principal;
          //  checkAfterBorrow(i, tBorrower);
        }

        // repay
        uint tTotal = currency.totalSupply();

        // allow pile full control over borrower tokens
        borrower.doApproveCurrency(address(shelf), uint(-1));

        uint distributorBalance = currency.balanceOf(address(distributor));
        for (uint i = 1; i <= 10; i++) {
            principal = i * 80;

            // repay transaction
            borrower.repayAction(i, principal);

            distributorBalance += principal;
            checkAfterRepay(i, i, tTotal, distributorBalance);
        }
    }

    function testFailBorrowSameTokenIdTwice() public {
        // collateralNFT value
        uint principal = 100;

        // create borrower collateral collateralNFT
        uint tokenId = collateralNFT.issue(borrower_);
        // borrower issue loans
        uint loan =  borrower.issue(collateralNFT_, tokenId);

        // admin define ceiling
        admin.setCeiling(loan, principal);
        borrower.approveNFT(collateralNFT, address(shelf));
        borrower.borrowAction(loan, principal);
        checkAfterBorrow(tokenId, principal);

        // should fail
        borrower.borrowAction(loan, principal);
    }

    function testFailBorrowNonExistingToken() public {
        borrower.borrowAction(42, 100);
        assertEq(currency.balanceOf(borrower_), 0);
    }

    function testFailBorrowNotWhitelisted() public {
        collateralNFT.issue(borrower_);
        borrower.borrowAction(1, 100);
        assertEq(currency.balanceOf(borrower_), 0);
    }

    function testFailAdmitNonExistingcollateralNFT() public {
        // borrower issue loan
        uint loan =  borrower.issue(collateralNFT_, 123);

        // admin define ceiling
        admin.setCeiling(loan, 100);
        borrower.borrowAction(loan, 100);
        assertEq(currency.balanceOf(borrower_), 0);
    }

    function testFailBorrowcollateralNFTNotApproved() public {
        uint tokenId = collateralNFT.issue(borrower_);
        // borrower issue loans
        uint loan =  borrower.issue(collateralNFT_, tokenId);

        // admin define ceiling
        admin.setCeiling(loan, 100);
        borrower.borrowAction(loan, 100);
        assertEq(currency.balanceOf(borrower_), 100);
    }
}
