"""Seed stability, control-flow construction and bounded inputs for stress."""
import argparse
import hashlib
import unittest
from stress_program import generate, KINDS, MIN_BLOCKS, MAX_BLOCKS
from run_reference_stress import parse_seeds, memory_access


class StressProgramTests(unittest.TestCase):
    def test_reproducibility_anchor(self):
        first,description=generate(1,16)
        self.assertEqual((first,description),generate(1,16))
        encoded=''.join(f'{word:08x}\n' for word in first).encode()
        self.assertEqual(hashlib.sha256(encoded).hexdigest(),
                         '93306ceb1cfd1481d4531a87398bae559f18a85452d240dd53356a243fb24441')
        self.assertNotEqual(first,generate(2,16)[0])
        self.assertEqual(description['generator_version'],1)

    def test_seed_and_block_bounds(self):
        for seed in [-1,1<<32,'1']:
            with self.assertRaises(ValueError): generate(seed,16)
        for blocks in [MIN_BLOCKS-1,MAX_BLOCKS+1,'120']:
            with self.assertRaises(ValueError): generate(1,blocks)
        self.assertEqual(parse_seeds('603e,1,deadbeef'),[0x603e,1,0xdeadbeef])
        for text in ['', '1,1','-1','100000000','xyz',','.join(f'{i:x}' for i in range(33))]:
            with self.assertRaises(argparse.ArgumentTypeError): parse_seeds(text)

    def test_full_bounded_images_and_categories(self):
        for seed in [0,1,0x603e,0xdeadbeef,0xffffffff]:
            words,description=generate(seed,MAX_BLOCKS)
            self.assertLess(len(words),16384)
            self.assertEqual(len(words),len(description['instructions']))
            self.assertTrue(set(KINDS).issubset({r['kind'] for r in description['instructions']}))
            for index,row in enumerate(description['instructions']):
                self.assertEqual(row['pc'],index*4)
                self.assertEqual(row['word'],f'{words[index]:08x}')
                self.assertLess(words[index],1<<32)

    def test_branch_targets_and_literal_call_shape(self):
        words,description=generate(0x603e,MAX_BLOCKS)
        for index,entry in enumerate(description['instructions']):
            word=words[index]
            if word>>26==16:
                displacement=word&0xfffc
                if displacement&0x8000: displacement-=65536
                target=index*4+displacement
                self.assertGreaterEqual(target,0);self.assertLess(target,len(words)*4)
                if entry['operation']=='bdnz-loop':
                    self.assertEqual(displacement,-8)
                    self.assertEqual(word,0x4200fff8)
                    self.assertEqual(words[index-3],0x7ec903a6) # mtctr r22
                    self.assertIn(words[index-4]&65535,range(1,6))
            if entry['operation']=='bl-call':
                self.assertEqual(word,0x48000009)
                self.assertEqual(words[index+1],0x48000008)
                self.assertIn(words[index+2],[0x4e800020,0x4e800021])
            if entry['operation']=='bcctr-forward':
                target=words[index-2]&65535
                self.assertEqual(target&~3,(index+2)*4)
                self.assertEqual(words[index-1],0x7ec903a6)

    def test_safe_divisor_and_access_counter_anchors(self):
        words,description=generate(0xdeadbeef,MAX_BLOCKS)
        for index,entry in enumerate(description['instructions']):
            if entry['operation']=='divide-dependent':
                self.assertEqual((words[index]>>11)&31,15)
                self.assertEqual(words[index-2]>>26,15)
                self.assertEqual(words[index-1]>>26,24)
                divisor=((words[index-2]&65535)<<16)|(words[index-1]&65535)
                self.assertIn(divisor,[1,3,7,31,65537,0x7fffffff])
        self.assertEqual(memory_access(0x80641000),(1,0)) # lwz
        self.assertEqual(memory_access(0x7c64216e),(1,1)) # stwux
        self.assertEqual(memory_access(0x38600001),(0,0)) # addi


if __name__=='__main__': unittest.main()
