import { expect } from "chai";
import { network } from "hardhat";
import { MaxUint256, ZeroAddress, ZeroHash, id } from "ethers";
import { checkInTypes } from "../scripts/signing.js";

const { ethers } = await network.create();

async function fixture(yieldEnabled = false, tokenName = "MockUSDC", adapterName = "MockYieldAdapter") {
  const [funder, merchant, customer, outsider, treasury] = await ethers.getSigners();
  const token = await ethers.deployContract(tokenName, [funder.address]);
  const adapter = yieldEnabled
    ? await ethers.deployContract(adapterName, [token.target, funder.address])
    : null;
  const vault = await ethers.deployContract("PrepaidVault", [token.target, treasury.address, adapter?.target ?? ZeroAddress]);
  if (adapter) await (await adapter.bindVault(vault.target)).wait();
  const vm = await ethers.getContractAt("PrepaidVault", vault.target, merchant);
  const vc = await ethers.getContractAt("PrepaidVault", vault.target, customer);
  const vo = await ethers.getContractAt("PrepaidVault", vault.target, outsider);
  const tc = await ethers.getContractAt(tokenName, token.target, customer);
  await token.mint(customer.address, 1_000_000_000n);
  await tc.approve(vault.target, MaxUint256);
  await vm.createPlan(id("gym"), token.target, 50_000_000n, 2, 10, 20);
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const domain = { name: "PrepaidGuard", version: "1", chainId, verifyingContract: String(vault.target) };

  async function at(timestamp: bigint) {
    await ethers.provider.send("evm_setNextBlockTimestamp", [Number(timestamp)]);
  }
  async function proof(subscriptionId = 1n, overrides = {}, signer = customer, signedDomain = domain) {
    const sub = await vault.getSubscription(subscriptionId);
    const message = {
      subscriptionId, merchant: merchant.address, periodIndex: sub.completedPeriods + 1n,
      nonce: sub.nonce, deadline: sub.nextReleaseAt + 600n, ...overrides,
    };
    return { message, signature: await signer.signTypedData(signedDomain, checkInTypes, message) };
  }
  return { funder, merchant, customer, outsider, treasury, token, tc, adapter, vault, vm, vc, vo, domain, at, proof };
}

describe("PrepaidVault", function () {
  this.timeout(60_000);

  it("validates terms, immutable plans and references scoped to each merchant", async () => {
    const f = await fixture();
    expect(await f.token.decimals()).to.equal(6);
    const invalid = [
      [ZeroHash, f.token.target, 1n, 2, 10, 20],
      [id("bad"), f.outsider.address, 1n, 2, 10, 20],
      [id("bad"), f.token.target, 0n, 2, 10, 20],
      [id("bad"), f.token.target, 1n, 0, 10, 20],
      [id("bad"), f.token.target, 1n, 121, 10, 20],
      [id("bad"), f.token.target, MaxUint256, 2, 10, 20],
      [id("bad"), f.token.target, 1n, 2, 0, 20],
      [id("bad"), f.token.target, 1n, 2, 10, 0],
      [id("bad"), f.token.target, 1n, 2, 2n ** 63n - 1n, 1],
    ];
    for (const args of invalid) await expect(f.vm.createPlan(...args)).to.be.revertedWithCustomError(f.vault, "InvalidTerms");
    await expect(f.vm.createPlan(id("gym"), f.token.target, 1n, 2, 10, 20))
      .to.be.revertedWithCustomError(f.vault, "DuplicateReference");
    await f.vo.createPlan(id("gym"), f.token.target, 1n, 2, 10, 20);
    expect((await f.vault.getPlan(1)).pricePerPeriod).to.equal(50_000_000n);
    expect((await f.vault.getPlan(2)).merchant).to.equal(f.outsider.address);
    await expect(f.vault.getPlan(0)).to.be.revertedWithCustomError(f.vault, "InvalidPlan");
    await expect(f.vault.getSubscription(0)).to.be.revertedWithCustomError(f.vault, "InvalidSubscription");
    await expect(f.vo.subscribe(0)).to.be.revertedWithCustomError(f.vault, "InvalidPlan");
    await expect(f.token.connect(f.outsider).getFunction("mint")(f.outsider.address, 1))
      .to.be.revertedWithCustomError(f.token, "OwnableUnauthorizedAccount");
    expect(f.vault.interface.hasFunction("withdraw")).to.equal(false);
    expect(f.vault.interface.hasFunction("mint")).to.equal(false);
    expect(f.vault.interface.hasFunction("setTime")).to.equal(false);
  });

  it("requires allowance and exact principal, allowing multiple subscriptions", async () => {
    const f = await fixture();
    await f.tc.approve(f.vault.target, 99_999_999n);
    await expect(f.vc.subscribe(1)).to.revert(ethers);
    expect(await f.vault.subscriptionCount()).to.equal(0);
    expect(await f.vault.totalPrincipal()).to.equal(0);
    await f.tc.approve(f.vault.target, MaxUint256);
    await expect(f.vc.subscribe(1)).to.emit(f.vault, "Subscribed");
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    expect(sub.subscriber).to.equal(f.customer.address);
    expect(sub.nextReleaseAt - sub.startedAt).to.equal(10);
    expect(sub.remainingPrincipal).to.equal(100_000_000n);
    expect(sub.nonce).to.equal(0);
    expect(await f.token.balanceOf(f.vault.target)).to.equal(200_000_000n);
    expect(await f.vault.totalPrincipal()).to.equal(200_000_000n);
  });

  it("releases exactly one period, schedules from the release, and completes once", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    let sub = await f.vault.getSubscription(1);
    let p = await f.proof();
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "CheckInWindowClosed");
    await f.at(sub.nextReleaseAt + 5n);
    const released = await (await f.vm.checkInWithSignature(p.message, p.signature)).wait();
    const block = await ethers.provider.getBlock(released.blockNumber);
    sub = await f.vault.getSubscription(1);
    expect(sub.nextReleaseAt).to.equal(BigInt(block!.timestamp) + 10n);
    expect(sub.completedPeriods).to.equal(1);
    expect(sub.nonce).to.equal(1);
    expect(await f.token.balanceOf(f.merchant.address)).to.equal(50_000_000n);
    await f.at(sub.nextReleaseAt);
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "InvalidCheckIn");
    p = await f.proof();
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.emit(f.vault, "PeriodReleased");
    sub = await f.vault.getSubscription(1);
    expect(sub.status).to.equal(2);
    expect(sub.remainingPrincipal).to.equal(0);
    expect(await f.vault.totalPrincipal()).to.equal(0);
    expect(await f.token.balanceOf(f.merchant.address)).to.equal(100_000_000n);
    await expect(f.vc.refund(1)).to.be.revertedWithCustomError(f.vault, "TerminalSubscription");
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "TerminalSubscription");
  });

  it("rejects wrong signer, caller, merchant, nonce, period and EIP-712 domain", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    await f.at(sub.nextReleaseAt);
    await ethers.provider.send("evm_mine", []);
    let p = await f.proof();
    await expect(f.vo.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "Unauthorized");
    p = await f.proof(1n, { merchant: f.outsider.address });
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "Unauthorized");
    for (const change of [{ nonce: 1n }, { periodIndex: 2n }]) {
      p = await f.proof(1n, change);
      await expect(f.vm.checkInWithSignature(p.message, p.signature))
        .to.be.revertedWithCustomError(f.vault, "InvalidCheckIn");
    }
    p = await f.proof(1n, {}, f.outsider);
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.be.revertedWithCustomError(f.vault, "InvalidSignature");
    for (const domain of [
      { ...f.domain, chainId: 43113n }, { ...f.domain, verifyingContract: f.outsider.address },
      { ...f.domain, name: "Wrong" }, { ...f.domain, version: "2" },
    ]) {
      p = await f.proof(1n, {}, f.customer, domain);
      await expect(f.vm.checkInWithSignature(p.message, p.signature))
        .to.be.revertedWithCustomError(f.vault, "InvalidSignature");
    }
    p = await f.proof();
    await expect(f.vm.checkInWithSignature(p.message, "0x1234")).to.revert(ethers);
    expect((await f.vault.getSubscription(1)).remainingPrincipal).to.equal(100_000_000n);
    expect(await f.token.balanceOf(f.merchant.address)).to.equal(0);
  });

  it("bounds QR deadlines to 900 seconds and accepts the exact deadline", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    let p = await f.proof(1n, { deadline: sub.nextReleaseAt - 1n });
    await f.at(sub.nextReleaseAt);
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.be.revertedWithCustomError(f.vault, "InvalidDeadline");
    const current = sub.nextReleaseAt;
    p = await f.proof(1n, { deadline: current + 902n });
    await f.at(current + 1n);
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.be.revertedWithCustomError(f.vault, "InvalidDeadline");
    const deadline = current + 2n;
    p = await f.proof(1n, { deadline });
    await f.at(deadline);
    await f.vm.checkInWithSignature(p.message, p.signature);
    expect((await f.vault.getSubscription(1)).nonce).to.equal(1);
  });

  it("opens refund at the exact boundary and closes check-in with no overlap", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    const boundary = sub.nextReleaseAt + 20n;
    const p = await f.proof(1n, { deadline: boundary + 10n });
    await expect(f.vo.refund(1)).to.be.revertedWithCustomError(f.vault, "Unauthorized");
    await f.at(boundary - 1n);
    await expect(f.vc.refund(1)).to.be.revertedWithCustomError(f.vault, "RefundNotAvailable");
    await f.at(boundary);
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.be.revertedWithCustomError(f.vault, "CheckInWindowClosed");
    await expect(f.vc.refund(1)).to.emit(f.vault, "Refunded")
      .withArgs(1, 1, 100_000_000n, 0, 0, 0, 1);
    expect((await f.vault.getSubscription(1)).status).to.equal(3);
    expect(await f.token.balanceOf(f.customer.address)).to.equal(1_000_000_000n);
    await expect(f.vc.refund(1)).to.be.revertedWithCustomError(f.vault, "TerminalSubscription");
    expect(await f.vault.totalPrincipal()).to.equal(0);
  });

  it("returns only unused principal after a partial release", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const p = await f.proof();
    await f.at((await f.vault.getSubscription(1)).nextReleaseAt);
    await f.vm.checkInWithSignature(p.message, p.signature);
    const sub = await f.vault.getSubscription(1);
    await f.at(sub.nextReleaseAt + 20n);
    await f.vc.refund(1);
    expect(await f.token.balanceOf(f.customer.address)).to.equal(950_000_000n);
    expect(await f.token.balanceOf(f.merchant.address)).to.equal(50_000_000n);
    expect(await f.token.balanceOf(f.vault.target)).to.equal(0);
    expect((await f.vault.getSubscription(1)).nonce).to.equal(2);
  });

  it("allocates backed yield per subscription and conserves rounding on release and refund", async () => {
    const f = await fixture(true);
    await f.vc.subscribe(1);
    await f.vc.subscribe(1);
    await f.token.mint(f.funder.address, 122n);
    await f.token.approve(f.adapter!.target, 122n);
    await expect(f.adapter!.connect(f.outsider).getFunction("fundYield")(1, 1))
      .to.be.revertedWithCustomError(f.adapter!, "Unauthorized");
    await f.adapter!.fundYield(1, 101);
    await f.adapter!.fundYield(2, 21);
    expect(await f.vault.estimateYield(1)).to.equal(101);
    expect(await f.vault.estimateYield(2)).to.equal(21);
    const p = await f.proof();
    await f.at((await f.vault.getSubscription(1)).nextReleaseAt);
    await expect(f.vm.checkInWithSignature(p.message, p.signature))
      .to.emit(f.vault, "PeriodReleased").withArgs(1, 1, 1, 50_000_000n, 70, 20, 11, 1,
        (await f.vault.getSubscription(1)).nextReleaseAt + 10n, false);
    expect(await f.adapter!.yieldOf(1)).to.equal(0);
    expect(await f.adapter!.yieldOf(2)).to.equal(21);
    expect(await f.adapter!.principalOf(2)).to.equal(100_000_000n);
    await f.at((await f.vault.getSubscription(2)).nextReleaseAt + 20n);
    await expect(f.vc.refund(2)).to.emit(f.vault, "Refunded")
      .withArgs(2, 1, 100_000_000n, 14, 4, 3, 1);
    expect(await f.token.balanceOf(f.treasury.address)).to.equal(14);
    expect(await f.token.balanceOf(f.adapter!.target)).to.equal(50_000_000n);
    expect(await f.adapter!.totalPrincipal()).to.equal(50_000_000n);
    expect(await f.adapter!.totalYield()).to.equal(0);
    expect(await f.token.balanceOf(f.vault.target)).to.equal(0);
    await expect(f.adapter!.fundYield(2, 1)).to.be.revertedWithCustomError(f.adapter!, "InvalidPosition");
    await expect(f.adapter!.withdraw(1, 1)).to.be.revertedWithCustomError(f.adapter!, "Unauthorized");
    await expect(f.adapter!.bindVault(f.vault.target)).to.be.revertedWithCustomError(f.adapter!, "InvalidVault");
  });

  it("reverts state and balances atomically when token transfer fails", async () => {
    const f = await fixture(false, "FailingToken");
    await f.vc.subscribe(1);
    const before = await f.vault.getSubscription(1);
    const p = await f.proof();
    await f.token.setFailTransfers(true);
    await f.at(before.nextReleaseAt);
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.revert(ethers);
    expect(await f.vault.getSubscription(1)).to.deep.equal(before);
    expect(await f.vault.totalPrincipal()).to.equal(100_000_000n);
    await f.at(before.nextReleaseAt + 20n);
    await expect(f.vc.refund(1)).to.revert(ethers);
    expect(await f.vault.getSubscription(1)).to.deep.equal(before);
    await f.token.setFailTransfers(false);
    await f.vc.refund(1);
    expect(await f.token.balanceOf(f.customer.address)).to.equal(1_000_000_000n);
  });

  it("rejects adapter shortfall instead of borrowing another subscriber's principal", async () => {
    const f = await fixture(true, "MockUSDC", "ShortAdapter");
    await f.vc.subscribe(1);
    await f.vc.subscribe(1);
    const before = await f.vault.getSubscription(1);
    const balance = await f.token.balanceOf(f.adapter!.target);
    const p = await f.proof();
    await f.at(before.nextReleaseAt);
    await expect(f.vm.checkInWithSignature(p.message, p.signature)).to.be.revertedWithCustomError(f.vault, "AdapterShortfall");
    expect(await f.vault.getSubscription(1)).to.deep.equal(before);
    expect(await f.token.balanceOf(f.adapter!.target)).to.equal(balance);
    expect(await f.vault.totalPrincipal()).to.equal(200_000_000n);
  });

  it("blocks token callbacks from reentering subscribe", async () => {
    const f = await fixture(false, "CallbackToken");
    await f.token.setCallback(f.vault.target, f.vault.interface.encodeFunctionData("subscribe", [1]));
    await f.vc.subscribe(1);
    expect(await f.token.callbackSucceeded()).to.equal(false);
    const selector = ethers.id("ReentrancyGuardReentrantCall()").slice(0, 10);
    expect(await f.token.callbackResult()).to.equal(selector);
    expect(await f.vault.subscriptionCount()).to.equal(1);
    expect(await f.token.balanceOf(f.vault.target)).to.equal(100_000_000n);
  });

  it("rejects fee-on-transfer principal and rolls back the entire subscription", async () => {
    const f = await fixture(false, "FeeToken");
    await expect(f.vc.subscribe(1)).to.be.revertedWithCustomError(f.vault, "UnsupportedToken");
    expect(await f.vault.subscriptionCount()).to.equal(0);
    expect(await f.vault.totalPrincipal()).to.equal(0);
    expect(await f.token.balanceOf(f.customer.address)).to.equal(1_000_000_000n);
  });

  it("consumes one nonce when two scans land in the same block", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    const p = await f.proof();
    const nonce = await f.merchant.getNonce();
    await ethers.provider.send("evm_setAutomine", [false]);
    try {
      const first = await f.vm.checkInWithSignature(p.message, p.signature, { gasLimit: 800_000, nonce });
      const second = await f.vm.checkInWithSignature(p.message, p.signature, { gasLimit: 800_000, nonce: nonce + 1 });
      await f.at(sub.nextReleaseAt);
      await ethers.provider.send("evm_mine", []);
      const receipts = await Promise.all([first, second].map((tx) =>
        ethers.provider.send("eth_getTransactionReceipt", [tx.hash])));
      expect(receipts.map((receipt) => receipt.status)).to.deep.equal(["0x1", "0x0"]);
      expect((await f.vault.getSubscription(1)).nonce).to.equal(1);
      expect(await f.token.balanceOf(f.merchant.address)).to.equal(50_000_000n);
    } finally {
      await ethers.provider.send("evm_setAutomine", [true]);
    }
  });

  it("settles only refund when check-in and refund land at the same boundary", async () => {
    const f = await fixture();
    await f.vc.subscribe(1);
    const sub = await f.vault.getSubscription(1);
    const p = await f.proof();
    await ethers.provider.send("evm_setAutomine", [false]);
    try {
      const release = await f.vm.checkInWithSignature(p.message, p.signature, { gasLimit: 800_000 });
      const refund = await f.vc.refund(1, { gasLimit: 800_000 });
      await f.at(sub.nextReleaseAt + 20n);
      await ethers.provider.send("evm_mine", []);
      const receipts = await Promise.all([release, refund].map((tx) =>
        ethers.provider.send("eth_getTransactionReceipt", [tx.hash])));
      expect(receipts.map((receipt) => receipt.status)).to.deep.equal(["0x0", "0x1"]);
      expect((await f.vault.getSubscription(1)).status).to.equal(3);
      expect(await f.token.balanceOf(f.merchant.address)).to.equal(0);
      expect(await f.token.balanceOf(f.customer.address)).to.equal(1_000_000_000n);
    } finally {
      await ethers.provider.send("evm_setAutomine", [true]);
    }
  });
});
