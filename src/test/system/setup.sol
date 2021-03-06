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

import {
  TitleFab,
  ShelfFab,
  PileFab,
  PrincipalCeilingFab,
  CreditLineCeilingFab,
  CeilingFab,
  ThresholdFab,
  CollectorFab,
  PricePoolFab,
  BorrowerDeployer
} from "../../borrower/deployer.sol";

import { Title } from "tinlake-title/title.sol";
import { Pile } from "../../borrower/pile.sol";
import { Shelf } from "../../borrower/shelf.sol";
import { Collector } from "../../borrower/collect/collector.sol";
import { Principal } from "../../borrower/ceiling/principal.sol";
import { CreditLine } from "../../borrower/ceiling/creditline.sol";

import {
  TrancheFab,
  SeniorTrancheFab,
  AllowanceOperatorFab,
  WhitelistOperatorFab,
  DefaultAssessorFab,
  ProportionalOperatorFab,
  FullInvestmentAssessorFab,
  DefaultDistributorFab,
  LenderDeployer
} from "../../lender/deployer.sol";
import { Tranche } from "../../lender/tranche/tranche.sol";
import { SeniorTranche } from "../../lender/tranche/senior_tranche.sol";

import { TestRoot } from "./root.sol";
import "../simple/token.sol";

import "tinlake-erc20/erc20.sol";
import { PushRegistry } from "tinlake-registry/registry.sol";
import { TokenLike, CeilingLike } from "./interfaces.sol";

contract DistributorLike {
    function borrowFromTranches() public returns (bool);
    function rely(address usr) public;
    function deny(address usr) public;
    function depend (bytes32 contractName, address addr) public;
    function file(bytes32 what, bool flag) public;
    function balance() public;
}

contract AuthLike {
    function rely(address) public;
    function deny(address) public;
}

contract TestSetup {
    Title public collateralNFT;
    address      public collateralNFT_;
    SimpleToken  public currency;
    address      public currency_;

    // Borrower contracts
    Shelf        shelf;
    Pile         pile;
    Title        title;
    CeilingLike    ceiling;
    Collector    collector;
    PushRegistry threshold;

    // Lender contracts
    Tranche          junior;
    SeniorTranche    senior;
    DistributorLike  distributor;
    TokenLike public juniorToken;
    address public   juniorOperator;
    TokenLike public seniorToken;
    address public   seniorOperator;
    address public   assessor;

    // Deployers
    BorrowerDeployer public borrowerDeployer;
    LenderDeployer public   lenderDeployer;

    TestRoot root;
    address  root_;

    function issueNFT(address usr) public returns (uint tokenId, bytes32 lookupId) {
        tokenId = collateralNFT.issue(usr);
        lookupId = keccak256(abi.encodePacked(collateralNFT_, tokenId));
        return (tokenId, lookupId);
    }

    function deployContracts(bytes32 operator_, bytes32 distributor_, bytes32 assessor_, bool senior_, bytes32 ceiling_, bytes32 seniorOperator_) public {
        collateralNFT = new Title("Collateral NFT", "collateralNFT");
        collateralNFT_ = address(collateralNFT);

        currency = new SimpleToken("C", "Currency", "1", 0);
        currency_ = address(currency);

        root = new TestRoot(address(this));
        root_ = address(root);
        // only admin is main deployer
        deployBorrower(ceiling_);
        // only admin is main deployer
        deployLender(operator_, distributor_, assessor_, senior_, seniorOperator_);

        root.prepare(address(lenderDeployer), address(borrowerDeployer), address(this));
        root.deploy();
    }

    function deployBorrower(bytes32 ceiling_) private {
        TitleFab titlefab = new TitleFab();
        ShelfFab shelffab = new ShelfFab();
        PileFab pileFab = new PileFab();
        CollectorFab collectorFab = new CollectorFab();
        ThresholdFab thresholdFab = new ThresholdFab();
        PricePoolFab pricePoolFab = new PricePoolFab();
        address ceilingFab_;

        if (ceiling_ == "default") {
            ceilingFab_ = address(new PrincipalCeilingFab());
        } else if (ceiling_ == "creditline") {
            ceilingFab_ = address(new CreditLineCeilingFab());
        }

        borrowerDeployer = new BorrowerDeployer(root_, titlefab, shelffab, pileFab, ceilingFab_, collectorFab, thresholdFab, pricePoolFab, address(0), currency_, "Tinlake Loan Token", "TLNT");

        borrowerDeployer.deployTitle();
        borrowerDeployer.deployPile();
        borrowerDeployer.deployCeiling();
        borrowerDeployer.deployShelf();
        borrowerDeployer.deployThreshold();
        borrowerDeployer.deployCollector();
        borrowerDeployer.deployPricePool();
        borrowerDeployer.deploy();

        shelf = Shelf(borrowerDeployer.shelf());
        pile = Pile(borrowerDeployer.pile());
        ceiling = CeilingLike(borrowerDeployer.ceiling());

        title = Title(borrowerDeployer.title());
        collector = Collector(borrowerDeployer.collector());
        threshold = PushRegistry(borrowerDeployer.threshold());
    }

    function deployLender(bytes32 operator_, bytes32 distributor_, bytes32 assessor_, bool senior_, bytes32 operatorSenior) public {
        address distributorFab_;
        address operatorFab_;
        address assessorFab_;
        address seniorOperatorFab_;
        address seniorTrancheFab_;

        if (operator_ == "whitelist") {
            operatorFab_ = address(new WhitelistOperatorFab());
        } else if (operator_ == "allowance") {
            operatorFab_ = address(new AllowanceOperatorFab());
        }

        if (distributor_ == "default") {
            distributorFab_ = address(new DefaultDistributorFab());
        }

        if (assessor_ == "default") {
            assessorFab_ = address(new DefaultAssessorFab());
        } else if (assessor_ == "full_investment") {
            assessorFab_ = address(new FullInvestmentAssessorFab());
        }

        if (senior_) {
            seniorTrancheFab_ = address(new SeniorTrancheFab());
            if(operatorSenior == "proportional") {

                seniorOperatorFab_ = address(new ProportionalOperatorFab());
            } else {
                // senior operator uses the same fab junior
                seniorOperatorFab_ = operatorFab_;
            }
        }


        uint tokenAmountForONE = 1;
        lenderDeployer = new LenderDeployer(root_, currency_, tokenAmountForONE, "TIN Token", "TIN", address(new TrancheFab()), assessorFab_,
            operatorFab_, distributorFab_, senior_);

        lenderDeployer.deployAssessor();
        lenderDeployer.deployDistributor();
        lenderDeployer.deployJuniorTranche();
        lenderDeployer.deployJuniorOperator();

        if (senior_) {
            uint ratePerSecond = 1000000564701133626865910626; // 5% per day
            lenderDeployer.initSenior(ratePerSecond,"DROP Token","DROP", seniorTrancheFab_,  seniorOperatorFab_);
            lenderDeployer.deploySeniorTranche();
            lenderDeployer.deploySeniorOperator();
        }

        lenderDeployer.deploy();

        distributor = DistributorLike(lenderDeployer.distributor());
        juniorOperator = lenderDeployer.juniorOperator();
        junior = Tranche(lenderDeployer.junior());
        juniorToken = TokenLike(address(junior.token()));
        assessor = lenderDeployer.assessor();
        if (senior_) {
            senior = SeniorTranche(lenderDeployer.senior());
            seniorOperator = lenderDeployer.seniorOperator();
            seniorToken = TokenLike(address(senior.token()));
        }
    }

}
