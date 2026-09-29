# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
import unittest
from reference import B32, B64, calculate, calculate_fma, pack


class ReferenceChecks(unittest.TestCase):
    def test_exact_add_and_cancellation(self):
        for rn in range(4):
            self.assertEqual(calculate('add', 0x3ff0000000000000, 0x3ff0000000000000, rn)['bits'], 0x4000000000000000)
            self.assertEqual(calculate('sub', 0x3ff0000000000000, 0x3ff0000000000000, rn)['bits'], (rn == 3) << 63)

    def test_halfway_and_directed_rounding(self):
        for rn, expected in enumerate((0x3f800000, 0x3f800000, 0x3f800001, 0x3f800000)):
            self.assertEqual(calculate('to32', 0x3ff0000010000000, 0, rn)['bits'], expected)
        self.assertEqual(calculate('to32', 0x3ff0000030000000, 0)['bits'], 0x3f800002)

    def test_gradual_underflow(self):
        self.assertEqual(calculate('mul', 0x0010000000000000, 0x3fe0000000000000)['bits'], 0x0008000000000000)
        self.assertFalse(calculate('mul', 0x0010000000000000, 0x3fe0000000000000)['uf'])
        tiny = calculate('mul', 1, 0x3fe0000000000000)
        self.assertEqual(tiny['bits'], 0)
        self.assertTrue(tiny['uf'] and tiny['nx'])

    def test_nan_and_infinity(self):
        self.assertEqual(calculate('add', 0xfff0000000000123, 0)['bits'], 0xfff8000000000123)
        self.assertTrue(calculate('mul', 0, B64.infinity)['invalid'])
        self.assertEqual(calculate('cmp', 0, 1 << 63)['bits'], 0)
        self.assertEqual(calculate('cmp', B64.infinity | 1, 0)['bits'], 3)

    def test_integer_bounds(self):
        self.assertEqual(calculate('i32tof', 0x80000000, 0)['bits'], 0xc1e0000000000000)
        self.assertEqual(calculate('ftoi32', 0xc1e0000000000000, 0)['bits'], 0x80000000)
        self.assertFalse(calculate('ftoi32', 0xc1e0000000000000, 0)['invalid'])
        self.assertTrue(calculate('ftoi32', 0x41e0000000000000, 0)['invalid'])

    def test_overflow_modes(self):
        for rn in range(4):
            for sign in range(2):
                bits, nx, uf, of, inc = pack(1, 1024, sign, rn)
                inf = rn == 0 or (rn == 2 and not sign) or (rn == 3 and sign)
                self.assertEqual(bits, (sign << 63) | (B64.infinity if inf else B64.infinity - 1))
                self.assertTrue(nx and of)
                self.assertFalse(uf)
                self.assertEqual(inc, inf)

    def test_widen_minimum_subnormal(self):
        self.assertEqual(calculate('to64', 1, 0, fmt=B32)['bits'], 0x36a0000000000000)

    def test_snan_payload_and_sign(self):
        for fmt in (B32, B64):
            sign = 1 << fmt.signbit
            snan = sign | fmt.infinity | 0x123
            result = calculate('add', snan, 0, fmt=fmt)
            self.assertEqual(result['bits'], snan | (1 << (fmt.fraction - 1)))
            self.assertTrue(result['invalid'])
            self.assertEqual(calculate('cmp', snan, 0, fmt=fmt)['bits'], 3)

    def test_rounding_across_minimum_normal(self):
        halfway = 0x380fffffe0000000
        for rn, bits, underflow in ((0, 0x00800000, False), (1, 0x007fffff, True),
                                    (2, 0x00800000, False), (3, 0x007fffff, True)):
            result = calculate('to32', halfway, 0, rn)
            self.assertEqual(result['bits'], bits)
            self.assertEqual(result['uf'], underflow)
            self.assertTrue(result['nx'])

    def test_exact_division_remainder(self):
        third = calculate('div', 0x3ff0000000000000, 0x4008000000000000)
        self.assertEqual(third['bits'], 0x3fd5555555555555)
        self.assertTrue(third['nx'])
        self.assertEqual(calculate('div', 0x3f800000, 0x40400000, fmt=B32)['bits'], 0x3eaaaaab)
        self.assertTrue(calculate('div', 0x3ff0000000000000, 0)['dz'])
        self.assertTrue(calculate('div', 0, 0)['invalid'])
        self.assertFalse(calculate('div', B64.infinity, 0)['dz'])

    def test_fused_cancellation(self):
        a, b, one = 0x3ff0000002000000, 0x3feffffffc000000, 0x3ff0000000000000
        for rn in range(4):
            fused = calculate_fma(a, b, one, rn, negate_addend=True)
            self.assertEqual(fused['bits'], 0xbc90000000000000)
            self.assertFalse(fused['nx'])
            rounded_product = calculate('mul', a, b, rn)['bits']
            rounded_difference = calculate('sub', rounded_product, one, rn)['bits']
            self.assertNotEqual(fused['bits'], rounded_difference)


if __name__ == '__main__':
    unittest.main()
