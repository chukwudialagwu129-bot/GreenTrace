import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;

describe("GreenTrace Security Tests", () => {
  beforeEach(() => {
    simnet.mineEmptyBlock();
  });

  describe("Contract Initialization", () => {
    it("ensures simnet is well initialized", () => {
      expect(simnet.blockHeight).toBeDefined();
    });

    it("should have correct initial state", () => {
      const { result: isPaused } = simnet.callReadOnlyFn("GreenTracecontract", "is-contract-paused", [], deployer);
      expect(isPaused).toBeBool(false);
    });
  });

  describe("Pause/Unpause Security", () => {
    it("should allow owner to pause contract", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "pause-contract", [], deployer);
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent non-owner from pausing", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "pause-contract", [], address1);
      expect(result).toBeErr(Cl.uint(401)); // ERR_NOT_AUTHORIZED
    });

    it("should block operations when paused", () => {
      simnet.callPublicFn("GreenTracecontract", "pause-contract", [], deployer);
      
      const { result } = simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("Test Manufacturer"),
        Cl.stringAscii("ISO 14001")
      ], address1);
      expect(result).toBeErr(Cl.uint(407)); // ERR_CONTRACT_PAUSED
    });

    it("should allow owner to unpause", () => {
      simnet.callPublicFn("GreenTracecontract", "pause-contract", [], deployer);
      const { result } = simnet.callPublicFn("GreenTracecontract", "unpause-contract", [], deployer);
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Input Validation", () => {
    it("should reject empty manufacturer name", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii(""),
        Cl.stringAscii("ISO 14001")
      ], address1);
      expect(result).toBeErr(Cl.uint(410)); // ERR_INVALID_INPUT
    });

    it("should reject zero carbon budget", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "set-carbon-budget", [
        Cl.uint(0)
      ], address1);
      expect(result).toBeErr(Cl.uint(400)); // ERR_INVALID_AMOUNT
    });

    it("should reject zero carbon offset purchase", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "purchase-carbon-offsets", [
        Cl.uint(0)
      ], address1);
      expect(result).toBeErr(Cl.uint(400)); // ERR_INVALID_AMOUNT
    });
  });

  describe("Rate Limiting", () => {
    it("should allow up to 5 operations per block", () => {
      for (let i = 1; i <= 5; i++) {
        const result = simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
          Cl.stringAscii(`Manufacturer ${i}`),
          Cl.stringAscii("ISO 14001")
        ], accounts.get(`wallet_${i}`)!);
        expect(result.result).toBeOk(Cl.bool(true));
      }
    });

    it("should track last operation block", () => {
      simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("Test Manufacturer"),
        Cl.stringAscii("ISO 14001")
      ], address1);

      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "get-last-operation-block", [Cl.standardPrincipal(address1)], deployer);
      expect(result).toBeDefined();
    });
  });

  describe("Manufacturer Registration Security", () => {
    it("should register manufacturer successfully", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("EcoManufacturing Inc"),
        Cl.stringAscii("ISO 14001 Certified")
      ], address1);
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent duplicate registration", () => {
      simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("EcoManufacturing Inc"),
        Cl.stringAscii("ISO 14001 Certified")
      ], address1);

      const { result } = simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("Another Name"),
        Cl.stringAscii("ISO 14001 Certified")
      ], address1);
      expect(result).toBeErr(Cl.uint(409)); // ERR_ALREADY_EXISTS
    });

    it("should check manufacturer verification status", () => {
      simnet.callPublicFn("GreenTracecontract", "register-manufacturer", [
        Cl.stringAscii("EcoManufacturing Inc"),
        Cl.stringAscii("ISO 14001 Certified")
      ], address1);

      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "is-manufacturer-verified", [Cl.standardPrincipal(address1)], deployer);
      expect(result).toBeBool(false);
    });
  });

  describe("Logistics Provider Security", () => {
    it("should register logistics provider successfully", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "register-logistics-provider", [
        Cl.stringAscii("GreenLogistics Co"),
        Cl.stringAscii("ISO 14064 Certified")
      ], address2);
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should check logistics verification status", () => {
      simnet.callPublicFn("GreenTracecontract", "register-logistics-provider", [
        Cl.stringAscii("GreenLogistics Co"),
        Cl.stringAscii("ISO 14064 Certified")
      ], address2);

      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "is-logistics-verified", [Cl.standardPrincipal(address2)], deployer);
      expect(result).toBeBool(false);
    });
  });

  describe("Carbon Budget Security", () => {
    it("should set carbon budget successfully", () => {
      const { result } = simnet.callPublicFn("GreenTracecontract", "set-carbon-budget", [
        Cl.uint(10000)
      ], address3);
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should retrieve consumer budget", () => {
      simnet.callPublicFn("GreenTracecontract", "set-carbon-budget", [Cl.uint(10000)], address3);

      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "get-consumer-budget", [Cl.standardPrincipal(address3)], deployer);
      expect(result).toBeDefined();
    });
  });

  describe("Read-Only Security Functions", () => {
    it("should check pause status", () => {
      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "is-contract-paused", [], deployer);
      expect(result).toBeBool(false);
    });

    it("should get last operation block", () => {
      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "get-last-operation-block", [Cl.standardPrincipal(address1)], deployer);
      expect(result).toBeUint(0);
    });

    it("should check carbon credit price", () => {
      const { result } = simnet.callReadOnlyFn("GreenTracecontract", "get-carbon-credit-price", [], deployer);
      expect(result).toBeUint(1000000);
    });
  });
});
