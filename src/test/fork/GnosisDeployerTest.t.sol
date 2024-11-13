pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {GnosisDeployer} from "../../deployer/GnosisDeployer.sol";

contract GnosisDeployerTest is Test {
    
    function testGnosisDeploy() public {
        GnosisDeployer deployer = new GnosisDeployer();
        address testAddr = vm.addr(0x12345);

        deployer.deploySafe(testAddr, testAddr, 1);
    }
}