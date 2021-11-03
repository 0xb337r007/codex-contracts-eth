const { expect } = require("chai")
const { ethers } = require("hardhat")

describe("Proofs", function () {

  const id = ethers.utils.randomBytes(32)
  const period = 10
  const timeout = 5

  let proofs

  beforeEach(async function () {
    const Proofs = await ethers.getContractFactory("TestProofs")
    proofs = await Proofs.deploy()
  })

  it("indicates that proofs are required", async function() {
    await proofs.expectProofs(id, period, timeout)
    expect(await proofs.period(id)).to.equal(period)
    expect(await proofs.timeout(id)).to.equal(timeout)
  })

  it("does not allow ids to be reused", async function() {
    await proofs.expectProofs(id, period, timeout)
    await expect(
      proofs.expectProofs(id, period, timeout)
    ).to.be.revertedWith("Proof id already in use")
  })

  it("does not allow a proof timeout that is too large", async function () {
    let invalidTimeout = 129 // max proof timeout is 128 blocks
    await expect(
      proofs.expectProofs(id, period, invalidTimeout)
    ).to.be.revertedWith("Invalid proof timeout")
  })

  describe("when proofs are required", async function () {

    beforeEach(async function () {
      await proofs.expectProofs(id, period, timeout)
    })

    async function mineBlock() {
      await ethers.provider.send("evm_mine")
    }

    async function minedBlockNumber() {
      return await ethers.provider.getBlockNumber()
    }

    async function mineUntilProofIsRequired(id) {
      while (!await proofs.isProofRequired(id, await minedBlockNumber())) {
        mineBlock()
      }
    }

    async function mineUntilProofTimeout() {
      for (let i=0; i<timeout; i++) {
        mineBlock()
      }
    }

    it("requires on average a proof every period", async function () {
      let blocks = 500
      let amount = 0
      for (i=0; i<blocks; i++) {
        await mineBlock()
        if (await proofs.isProofRequired(id, await minedBlockNumber())) {
          amount += 1
        }
      }
      let average = blocks / amount
      expect(average).to.be.closeTo(period, period / 2)
    })

    it("requires no proof for blocks that are unavailable", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      for (i=0; i<256; i++) { // only last 256 blocks are available in solidity
        mineBlock()
      }
      expect(await proofs.isProofRequired(id, blocknumber)).to.be.false
    })

    it("submits a correct proof", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await proofs.submitProof(id, blocknumber, true)
    })

    it("fails proof submission when proof is incorrect", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await expect(
        proofs.submitProof(id, blocknumber, false)
      ).to.be.revertedWith("Invalid proof")
    })

    it("fails proof submission when proof was not required", async function () {
      while (await proofs.isProofRequired(id, await minedBlockNumber())) {
        await mineBlock()
      }
      let blocknumber = await minedBlockNumber()
      await expect(
        proofs.submitProof(id, blocknumber, true)
      ).to.be.revertedWith("No proof required")
    })

    it("fails proof submission when proof is too late", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await mineUntilProofTimeout()
      await expect(
        proofs.submitProof(id, blocknumber, true)
      ).to.be.revertedWith("Proof not allowed after timeout")
    })

    it("fails proof submission when already submitted", async function() {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await proofs.submitProof(id, blocknumber, true)
      await expect(
        proofs.submitProof(id, blocknumber, true)
      ).to.be.revertedWith("Proof already submitted")
    })

    it("marks a proof as missing", async function () {
      expect(await proofs.missed(id)).to.equal(0)
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await mineUntilProofTimeout()
      await proofs.markProofAsMissing(id, blocknumber)
      expect(await proofs.missed(id)).to.equal(1)
    })

    it("does not mark a proof as missing before timeout", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await mineBlock()
      await expect(
        proofs.markProofAsMissing(id, blocknumber)
      ).to.be.revertedWith("Proof has not timed out yet")
    })

    it("does not mark a submitted proof as missing", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await proofs.submitProof(id, blocknumber, true)
      await mineUntilProofTimeout()
      await expect(
        proofs.markProofAsMissing(id, blocknumber)
      ).to.be.revertedWith("Proof was submitted, not missing")
    })

    it("does not mark proof as missing when not required", async function () {
      while (await proofs.isProofRequired(id, await minedBlockNumber())) {
        mineBlock()
      }
      let blocknumber = await minedBlockNumber()
      await mineUntilProofTimeout()
      await expect(
        proofs.markProofAsMissing(id, blocknumber)
      ).to.be.revertedWith("Proof was not required")
    })

    it("does not mark proof as missing twice", async function () {
      await mineUntilProofIsRequired(id)
      let blocknumber = await minedBlockNumber()
      await mineUntilProofTimeout()
      await proofs.markProofAsMissing(id, blocknumber)
      await expect(
        proofs.markProofAsMissing(id, blocknumber)
      ).to.be.revertedWith("Proof already marked as missing")
    })
  })
})
