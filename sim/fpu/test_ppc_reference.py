# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
import unittest
from ppc_reference import arithmetic, DEFAULT_NAN, SNAN, VC, CVI, IMZ


class PowerPCReferenceChecks(unittest.TestCase):
    def test_fused_architectural_operand_order(self):
        one = 0x3ff0000000000000
        a = 0x3ff0000002000000
        c = 0x3feffffffc000000
        result = arithmetic('msub', a, one, c)
        self.assertEqual(result['result'], 0xbc90000000000000)
        self.assertFalse(result['xx'])
        for rn in range(4):
            deep = arithmetic('madd', 0x3ff0000000000001,
                              0xbff0000000000000, 0x3feffffffffffffe, rn)
            self.assertEqual(deep['result'], 0xb970000000000000)
            self.assertFalse(deep['xx'])
            single = arithmetic('madd', 0x3ff0000020000000,
                                0xbff0000000000000, 0x3fefffffc0000000,
                                rn, single=True)
            self.assertEqual(single['result'], 0xbd10000000000000)
            self.assertFalse(single['xx'])

    def test_single_fused_rounds_once(self):
        a = 0x3ff8000000000000
        c = 0x3ff0000020000000
        b = 0xbaf0000000000000
        result = arithmetic('madd', a, b, c, single=True)
        self.assertEqual(result['result'], 0x3ff8000020000000)
        self.assertTrue(result['xx'])

    def test_fused_product_low_bit_survives_cancellation(self):
        for rn in range(4):
            double = arithmetic('madd', 0x3ff0000000000001,
                                0xbff0000000000002,
                                0x3ff0000000000001, rn)
            self.assertEqual(double['result'], 0x3970000000000000)
            self.assertFalse(double['xx'])
            single = arithmetic('madd', 0x3ff0000020000000,
                                0xbff0000040000000,
                                0x3ff0000020000000, rn, single=True)
            self.assertEqual(single['result'], 0x3d10000000000000)
            self.assertFalse(single['xx'])

    def test_negative_fused_negates_after_rounding(self):
        a, b, c = 0x3ff0000000000000, 0x3ca0000000000000, 0x3ff0000000000000
        positive = arithmetic('madd', a, b, c, rn=2)
        negative = arithmetic('nmadd', a, b, c, rn=2)
        self.assertEqual(negative['result'], positive['result'] ^ (1 << 63))
        self.assertEqual(negative['fr'], positive['fr'])
        self.assertEqual(negative['fi'], positive['fi'])

    def test_nan_priority_and_enabled_invalid(self):
        a = 0xfff8000000000123
        b = 0x7ff0000000000456
        result = arithmetic('madd', a, b, 0x3ff0000000000000)
        self.assertEqual(result['result'], a)
        self.assertEqual(result['invalid'], SNAN)
        self.assertFalse(arithmetic('madd', a, b, 0x3ff0000000000000, ve=True)['write_result'])
        self.assertEqual(arithmetic('mul', 0, 0, 0x7ff0000000000000)['result'], DEFAULT_NAN)
        both = arithmetic('madd', 0, b, 0x7ff0000000000000)
        self.assertEqual(both['invalid'], SNAN | IMZ)
        self.assertEqual(both['result'], b | (1 << 51))
        self.assertTrue(both['frfi_valid'])
        self.assertEqual(arithmetic('frsp', 0, 0x7ff0000000000000)['result'], 0x7ff0000000000000)
        opposite = arithmetic('madd', 0x7ff0000000000000,
                              0xfff0000000000000, 0x3ff0000000000000)
        self.assertEqual(opposite['invalid'], 1 << 1)
        self.assertEqual(opposite['result'], DEFAULT_NAN)

    def test_compare_nan_causes(self):
        qnan = 0x7ff8000000000001
        ordered = arithmetic('cmpo', qnan, 0)
        unordered = arithmetic('cmpu', qnan, 0)
        self.assertEqual(ordered['invalid'], VC)
        self.assertEqual(unordered['invalid'], 0)
        self.assertEqual(ordered['fpcc'], 1)
        self.assertEqual(arithmetic('cmpu', 0, 1 << 63)['fpcc'], 2)
        snan = 0x7ff0000000000001
        for left, right in ((snan, qnan), (qnan, snan)):
            self.assertEqual(arithmetic('cmpo', left, right)['invalid'], SNAN | VC)
            self.assertEqual(arithmetic('cmpo', left, right, ve=True)['invalid'], SNAN)

    def test_before_rounding_tininess_and_ni(self):
        midpoint = 0x380fffffe0000000
        result = arithmetic('frsp', 0, midpoint)
        self.assertEqual(result['result'], 0x3810000000000000)
        self.assertTrue(result['ux'] and result['xx'])
        sub = 0x36a0000000000000
        self.assertEqual(arithmetic('frsp', 0, sub)['result'], sub)
        self.assertEqual(arithmetic('frsp', 0, sub, ni=True)['result'], 0)

    def test_integer_boundary_after_rounding(self):
        positive_limit_plus_quarter = 0x41dfffffffc80000
        nearest = arithmetic('fctiw', 0, positive_limit_plus_quarter, rn=0)
        toward_zero = arithmetic('fctiw', 0, positive_limit_plus_quarter, rn=1)
        upward = arithmetic('fctiw', 0, positive_limit_plus_quarter, rn=2)
        self.assertEqual(nearest['result'] & 0xffffffff, 0x7fffffff)
        self.assertEqual(toward_zero['result'] & 0xffffffff, 0x7fffffff)
        self.assertEqual(upward['result'] & 0xffffffff, 0x7fffffff)
        self.assertEqual(upward['invalid'], CVI)
        self.assertFalse(arithmetic('fctiw', 0, positive_limit_plus_quarter, rn=2, ve=True)['write_result'])

    def test_enabled_exponent_adjustment_exact(self):
        sp_overflow = arithmetic('frsp', 0, 0x47f0000000000000, oe=True)
        self.assertEqual(sp_overflow['result'], 0x3bf0000000000000)
        self.assertTrue(sp_overflow['ox'])
        self.assertFalse(sp_overflow['xx'])
        sp_underflow = arithmetic('frsp', 0, 0x3800000000000000, ue=True)
        self.assertEqual(sp_underflow['result'], 0x4400000000000000)
        self.assertTrue(sp_underflow['ux'])
        self.assertFalse(sp_underflow['xx'])
        dp_overflow = arithmetic('mul', 0x7fe0000000000000, 0, 0x4000000000000000, oe=True)
        self.assertEqual(dp_overflow['result'], 0x1ff0000000000000)
        self.assertTrue(dp_overflow['ox'])
        self.assertFalse(dp_overflow['xx'])
        dp_underflow = arithmetic('mul', 0x0010000000000000, 0, 0x3fe0000000000000, ue=True)
        self.assertEqual(dp_underflow['result'], 0x6000000000000000)
        self.assertTrue(dp_underflow['ux'])
        self.assertFalse(dp_underflow['xx'])

    def test_single_subnormal_fprf_before_widening(self):
        result = arithmetic('frsp', 0, 0x36a0000000000000)
        self.assertEqual(result['result'], 0x36a0000000000000)
        self.assertEqual(result['fprf'], 0b10100)

    def test_fused_nan_factor_is_not_infinity_subtraction(self):
        inf, qnan = 0x7ff0000000000000, 0x7ff8000000000000
        for op in ('madd', 'msub', 'nmadd', 'nmsub'):
            for a, c in ((qnan, inf), (inf, qnan), (inf | 1 << 63, qnan)):
                for b in (inf, inf | 1 << 63):
                    result = arithmetic(op, a, b, c, ve=True)
                    self.assertEqual(result['invalid'], 0)
                    self.assertTrue(result['write_result'])
                    self.assertEqual(result['result'], qnan)


if __name__ == '__main__':
    unittest.main()
