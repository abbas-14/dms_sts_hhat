import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DeployOptions, IDeployDexesResult } from "../helpers/interfaces";
import { run } from "hardhat";
import { Contract } from "ethers";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    await run('compile');
    const { deployments, getNamedAccounts, getUnnamedAccounts } = hre;
    const { deploy } = deployments;
    // const { deployer } = await getNamedAccounts();
    const unnamedAccounts = await getUnnamedAccounts();
    
    const deployer = unnamedAccounts[0];
    let deployOptions: DeployOptions = {
      deploy,
      deployer,
    }
    
    const test = await deploy('Test1', {
      contract: 'Test',
      from: deployer,
      args: [],
      log: true,
      skipIfAlreadyDeployed: true,
      gasLimit: '10000000'
    });

    console.log('Deployed Test: ', test.address)
};
export default func;
