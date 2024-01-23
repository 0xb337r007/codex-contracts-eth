// Copyright 2017 Christian Reitwiessner
// Copyright 2019 OKIMS
// Copyright 2024 Codex
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
library Pairing {
  // The prime q in the base field F_q for G1
  uint constant private q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
  struct G1Point {
    uint x;
    uint y;
  }
  // Encoding of field elements is: x[0] * z + x[1]
  struct G2Point {
    uint[2] x;
    uint[2] y;
  }
  /// The negation of p, i.e. p.addition(p.negate()) should be zero.
  function negate(G1Point memory p) internal pure returns (G1Point memory) {
    if (p.x == 0 && p.y == 0)
      return G1Point(0, 0);
    return G1Point(p.x, q - (p.y % q));
  }
  /// The sum of two points of G1
  function addition(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
    uint[4] memory input;
    input[0] = p1.x;
    input[1] = p1.y;
    input[2] = p2.x;
    input[3] = p2.y;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
      // Use "invalid" to make gas estimation work
      switch success case 0 { invalid() }
    }
    require(success,"pairing-add-failed");
  }
  /// The product of a point on G1 and a scalar, i.e.
  /// p == p.scalar_mul(1) and p.addition(p) == p.scalar_mul(2) for all points p.
  function scalar_mul(G1Point memory p, uint s) internal view returns (G1Point memory r) {
    uint[3] memory input;
    input[0] = p.x;
    input[1] = p.y;
    input[2] = s;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
      // Use "invalid" to make gas estimation work
      switch success case 0 { invalid() }
    }
    require (success,"pairing-mul-failed");
  }
  /// The result of computing the pairing check
  /// e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
  /// For example pairing([P1(), P1().negate()], [P2(), P2()]) should
  /// return true.
  function pairing(G1Point[] memory p1, G2Point[] memory p2) internal view returns (bool) {
    require(p1.length == p2.length,"pairing-lengths-failed");
    uint elements = p1.length;
    uint inputSize = elements * 6;
    uint[] memory input = new uint[](inputSize);
    for (uint i = 0; i < elements; i++)
    {
      input[i * 6 + 0] = p1[i].x;
      input[i * 6 + 1] = p1[i].y;
      input[i * 6 + 2] = p2[i].x[0];
      input[i * 6 + 3] = p2[i].x[1];
      input[i * 6 + 4] = p2[i].y[0];
      input[i * 6 + 5] = p2[i].y[1];
    }
    uint[1] memory out;
    bool success;
    // solium-disable-next-line security/no-inline-assembly
    assembly {
      success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
      // Use "invalid" to make gas estimation work
      switch success case 0 { invalid() }
    }
    require(success,"pairing-opcode-failed");
    return out[0] != 0;
  }
  /// Convenience method for a pairing check for two pairs.
  function pairingProd2(G1Point memory a1, G2Point memory a2, G1Point memory b1, G2Point memory b2) internal view returns (bool) {
    G1Point[] memory p1 = new G1Point[](2);
    G2Point[] memory p2 = new G2Point[](2);
    p1[0] = a1;
    p1[1] = b1;
    p2[0] = a2;
    p2[1] = b2;
    return pairing(p1, p2);
  }
  /// Convenience method for a pairing check for three pairs.
  function pairingProd3(
      G1Point memory a1, G2Point memory a2,
      G1Point memory b1, G2Point memory b2,
      G1Point memory c1, G2Point memory c2
  ) internal view returns (bool) {
    G1Point[] memory p1 = new G1Point[](3);
    G2Point[] memory p2 = new G2Point[](3);
    p1[0] = a1;
    p1[1] = b1;
    p1[2] = c1;
    p2[0] = a2;
    p2[1] = b2;
    p2[2] = c2;
    return pairing(p1, p2);
  }
  /// Convenience method for a pairing check for four pairs.
  function pairingProd4(
      G1Point memory a1, G2Point memory a2,
      G1Point memory b1, G2Point memory b2,
      G1Point memory c1, G2Point memory c2,
      G1Point memory d1, G2Point memory d2
  ) internal view returns (bool) {
    G1Point[] memory p1 = new G1Point[](4);
    G2Point[] memory p2 = new G2Point[](4);
    p1[0] = a1;
    p1[1] = b1;
    p1[2] = c1;
    p1[3] = d1;
    p2[0] = a2;
    p2[1] = b2;
    p2[2] = c2;
    p2[3] = d2;
    return pairing(p1, p2);
  }
}
contract Verifier {
  using Pairing for *;
  uint256 constant private snark_scalar_field = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
  VerifyingKey private verifyingKey;
  struct VerifyingKey {
    Pairing.G1Point alpha1;
    Pairing.G2Point beta2;
    Pairing.G2Point gamma2;
    Pairing.G2Point delta2;
    Pairing.G1Point[] IC;
  }
  struct Proof {
    Pairing.G1Point A;
    Pairing.G2Point B;
    Pairing.G1Point C;
  }
  constructor() {
    verifyingKey.alpha1 = Pairing.G1Point(<%vk_alpha1%>);
    verifyingKey.beta2 = Pairing.G2Point(<%vk_beta2%>);
    verifyingKey.gamma2 = Pairing.G2Point(<%vk_gamma2%>);
    verifyingKey.delta2 = Pairing.G2Point(<%vk_delta2%>);
    <%vk_ic_pts%>
  }
  function verify(uint[] memory input, Proof memory proof) internal view returns (uint) {
    require(input.length + 1 == verifyingKey.IC.length,"verifier-bad-input");
    // Compute the linear combination vk_x
    Pairing.G1Point memory vk_x = Pairing.G1Point(0, 0);
    for (uint i = 0; i < input.length; i++) {
      require(input[i] < snark_scalar_field,"verifier-gte-snark-scalar-field");
      vk_x = Pairing.addition(vk_x, Pairing.scalar_mul(verifyingKey.IC[i + 1], input[i]));
    }
    vk_x = Pairing.addition(vk_x, verifyingKey.IC[0]);
    if (!Pairing.pairingProd4(
      Pairing.negate(proof.A), proof.B,
      verifyingKey.alpha1, verifyingKey.beta2,
      vk_x, verifyingKey.gamma2,
      proof.C, verifyingKey.delta2
    )) return 1;
    return 0;
  }
  function verifyProof(
      uint[2] memory a,
      uint[2][2] memory b,
      uint[2] memory c,
      uint[<%vk_input_length%>] memory input
    ) public view returns (bool r) {
    Proof memory proof;
    proof.A = Pairing.G1Point(a[0], a[1]);
    proof.B = Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
    proof.C = Pairing.G1Point(c[0], c[1]);
    uint[] memory inputValues = new uint[](input.length);
    for(uint i = 0; i < input.length; i++){
      inputValues[i] = input[i];
    }
    if (verify(inputValues, proof) == 0) {
      return true;
    } else {
      return false;
    }
  }
}
