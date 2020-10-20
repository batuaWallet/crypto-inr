import { BigNumber, utils, Wallet } from "ethers";

import { AddressBook } from "../addressBook";

import { createUniswapPair } from "./uniswapPair";
import { deployContracts } from "./contracts";

const { parseEther, parseUnits } = utils;

export const deployPep = async (wallet: Wallet, addressBook: AddressBook): Promise<void> => {
  console.log(`\nGetting Pep`);

  await deployContracts(wallet, addressBook, [
    ["Pep", []],
  ]);
  const pep = addressBook.getContract("Pep").connect(wallet);

  console.log(`Pep price ready? ${await pep.ready()}`);

  // Next step: deploy a uniswap oracle
  // Last step: call pep.init(pair, isGovZero);

};

export const initPep = async (wallet: Wallet, addressBook: AddressBook): Promise<void> => {
  const gov = addressBook.getContract("Gov").connect(wallet);
  const sai = addressBook.getContract("Sai").connect(wallet);
  const govAmt = parseEther("100");
  const govPrice = "100";

  await createUniswapPair({
    Gov: govAmt,
    Sai: govAmt.mul(govPrice),
  }, wallet, addressBook);
  const pair = addressBook.getContract("UniswapPair-GovSai").connect(wallet);

  const token0 = await pair.token0();
  const token1 = await pair.token1();
  const govIsIndexZero = gov.address == token0;
  if (!govIsIndexZero && gov.address != token1) {
    throw new Error(`Gov=${gov.address} !== token0=${token0} or token1=${token1}`);
  }

  const pep = addressBook.getContract("Pep").connect(wallet);
  const ready = await pep.ready();
  if (!ready) {
    console.log(`Initializing Pep`);
    await pep.init(pair.address, govIsIndexZero);
  }
  let [val, has] = await pep.peek();
  console.log(`Pep ready=${has} value=${val}`);


  // Swap to register uniswap price updates
  let saiBal, govBal;
  [saiBal, govBal] = [await sai.balanceOf(wallet.address), await gov.balanceOf(wallet.address)];

  const inAmt = "100";
  console.log(`\nSwapping ${inAmt} gov for sai (saiBal=${saiBal} govBal=${govBal})`);
  const uniswap = addressBook.getContract("UniswapRouter").connect(wallet);
  await(await gov["approve(address,uint256)"](uniswap.address, parseEther(inAmt))).wait();
  await(await uniswap.swapExactTokensForTokens(
    inAmt,
    inAmt,
    [gov.address, sai.address],
    wallet.address,
    BigNumber.from(Date.now() + 1000 * 60),
    { gasLimit: parseUnits("50", 6) },
  )).wait();
  const saiDiff = (await sai.balanceOf(wallet.address)).sub(saiBal);
  [saiBal, govBal] = [await sai.balanceOf(wallet.address), await gov.balanceOf(wallet.address)];
  console.log(`Received ${saiDiff} new sai (saiBal=${saiBal} govBal=${govBal})`);

  const outAmt = "100";
  console.log(`\nSwapping gov for ${outAmt} sai`);
  await(await sai["approve(address,uint256)"](uniswap.address, parseEther(outAmt))).wait();
  await(await uniswap.swapTokensForExactTokens(
    outAmt,
    parseEther(outAmt),
    [sai.address, gov.address],
    wallet.address,
    BigNumber.from(Date.now() + 1000 * 60),
    { gasLimit: parseUnits("50", 6) },
  )).wait();
  const govDiff = (await gov.balanceOf(wallet.address)).sub(govBal);
  [saiBal, govBal] = [await sai.balanceOf(wallet.address), await gov.balanceOf(wallet.address)];
  console.log(`Spent ${govDiff} gov (saiBal=${saiBal} govBal=${govBal})`);

  console.log(`Poking pep..`);
  await (await pep.poke()).wait();
  console.log(`Peeking pep..`);
  [val, has] = await pep.peek();
  console.log(`Pep ready=${has} value=${val}`);
  console.log(`\nPep price: ${BigNumber.from(val)}`);

};